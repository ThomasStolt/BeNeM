import Compression
import CryptoKit
import Foundation

@MainActor
final class DeepLinkHandler: ObservableObject {

    struct PendingImport {
        let bhnmURL: String          // direct BHNM server URL (from "bhnm_url" key)
        let middlewareURL: String    // push middleware URL (from "middleware_url" key); "" if absent
        let notificationsEnabled: Bool
        let apiKey: String
        let pin: String              // "" if absent
        let ackUser: String
        let name: String             // "" if absent — falls back to hostname
        let pushSecret: String       // "" if absent
        let symbol: String           // SF Symbol name; default "server.rack"
        let accentColor: String      // hex colour; default "#0A84FF"
    }

    @Published var pendingImport: PendingImport? = nil
    @Published var importError: String? = nil

    // MARK: - Public API

    func handle(url: URL) {
        guard url.scheme == "benem", url.host == "configure" else { return }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            fail("The link is missing required fields.")
            return
        }

        func param(_ name: String) -> String? {
            queryItems.first(where: { $0.name == name })?.value
        }

        // New compact format: single encrypted+compressed payload
        if let blob = param("p"), !blob.isEmpty {
            handleCompactPayload(blob)
            return
        }

        guard let server = param("server"), !server.isEmpty,
              let encryptedKey = param("api_key"), !encryptedKey.isEmpty else {
            fail("The link is missing required fields.")
            return
        }

        guard server.hasPrefix("http://") || server.hasPrefix("https://") else {
            fail("The link contains an invalid server URL.")
            return
        }

        let encryptedPin    = param("pin") ?? ""
        let ackUser         = param("ack_user") ?? "enter user name"
        let name            = param("name") ?? ""
        let encryptedSecret = param("push_secret") ?? ""

        do {
            let symmetricKey   = try loadKey()
            let decryptedKey    = try decrypt(encryptedKey, using: symmetricKey)
            let decryptedPin    = encryptedPin.isEmpty    ? "" : try decrypt(encryptedPin, using: symmetricKey)
            let decryptedSecret = encryptedSecret.isEmpty ? "" : try decrypt(encryptedSecret, using: symmetricKey)
            pendingImport = PendingImport(
                bhnmURL:              "",         // legacy links don't carry bhnmURL — migration banner will show
                middlewareURL:        server,
                notificationsEnabled: false,      // migration default
                apiKey:               decryptedKey,
                pin:                  decryptedPin,
                ackUser:              ackUser,
                name:                 name,
                pushSecret:           decryptedSecret,
                symbol:               "server.rack",
                accentColor:          "#0A84FF"
            )
        } catch {
            fail("The link is invalid or was created with a different key.")
        }
    }

    func applyPendingImport() {
        guard let imp = pendingImport else { return }

        let ud = UserDefaults.standard

        // 1. Write active AppStorage keys
        ud.set(imp.middlewareURL,  forKey: "netreo_base_url")
        ud.set(imp.bhnmURL,        forKey: "netreo_bhnm_url")
        ud.set(imp.apiKey,         forKey: "netreo_api_key")
        ud.set(imp.pin,            forKey: "netreo_pin")
        ud.set(imp.ackUser,        forKey: "netreo_ack_user")
        if !imp.pushSecret.isEmpty {
            ud.set(imp.pushSecret, forKey: "netreo_webhook_secret")
        }

        // 2. Upsert SavedConnection — match by bhnmURL (case-insensitive)
        //    If bhnmURL is empty (backward compat import), fall back to matching by middlewareURL
        var connections = ud.loadSavedConnections()
        let upsertedID: UUID
        let matchIdx: Int?
        if !imp.bhnmURL.isEmpty {
            let bhnmLower = imp.bhnmURL.lowercased()
            matchIdx = connections.firstIndex(where: { $0.bhnmURL.lowercased() == bhnmLower })
        } else {
            let mwLower = imp.middlewareURL.lowercased()
            matchIdx = connections.firstIndex(where: { $0.middlewareURL.lowercased() == mwLower })
        }

        if let idx = matchIdx {
            if !imp.name.isEmpty { connections[idx].name = imp.name }
            connections[idx].bhnmURL              = imp.bhnmURL
            connections[idx].middlewareURL        = imp.middlewareURL
            connections[idx].notificationsEnabled = imp.notificationsEnabled
            connections[idx].apiKey               = imp.apiKey
            connections[idx].pin                  = imp.pin
            connections[idx].ackUser              = imp.ackUser
            if !imp.pushSecret.isEmpty { connections[idx].webhookSecret = imp.pushSecret }
            connections[idx].symbol               = imp.symbol
            connections[idx].accentColor          = imp.accentColor
            upsertedID = connections[idx].id
        } else {
            let name = imp.name.isEmpty
                ? (URL(string: imp.bhnmURL.isEmpty ? imp.middlewareURL : imp.bhnmURL)?.host ?? imp.bhnmURL)
                : imp.name
            let newConn = SavedConnection(
                id: UUID(),
                name: name,
                middlewareURL: imp.middlewareURL,
                bhnmURL: imp.bhnmURL,
                notificationsEnabled: imp.notificationsEnabled,
                apiKey: imp.apiKey,
                pin: imp.pin,
                ackUser: imp.ackUser,
                webhookSecret: imp.pushSecret,
                symbol: imp.symbol,
                accentColor: imp.accentColor
            )
            connections.append(newConn)
            upsertedID = newConn.id
        }

        ud.saveSavedConnections(connections)
        ud.set(upsertedID.uuidString, forKey: "netreo_active_connection_id")

        // 3. Re-register push if notificationsEnabled
        if imp.notificationsEnabled,
           let token = AppDelegate.shared?.cachedDeviceToken,
           let conn = connections.first(where: { $0.id == upsertedID }) {
            AppDelegate.shared?.registerWithMiddleware(
                token: token,
                secret: conn.webhookSecret,
                middlewareURL: conn.middlewareURL
            )
        }

        pendingImport = nil
        NotificationCenter.default.post(name: .deepLinkConnectionApplied, object: nil)
    }

    // MARK: - Private

    private func fail(_ message: String) {
        importError = message
    }

    private func loadKey() throws -> SymmetricKey {
        guard let keyData = Data(hexString: Secrets.encryptionKey), keyData.count == 32 else {
            throw CryptoError.invalidKey
        }
        return SymmetricKey(data: keyData)
    }

    private func handleCompactPayload(_ blob: String) {
        do {
            let symmetricKey = try loadKey()
            let decrypted = try decryptToData(blob, using: symmetricKey)
            let decompressed = try zlibDecompress(decrypted)
            guard let json = try JSONSerialization.jsonObject(with: decompressed) as? [String: Any] else {
                fail("The link payload could not be parsed.")
                return
            }
            func str(_ key: String, default def: String = "") -> String {
                (json[key] as? String) ?? def
            }

            // New keys: bhnm_url + middleware_url
            // Backward compat: old links have "server" (= middleware URL) but no "bhnm_url"
            let bhnmURL: String
            let middlewareURL: String
            if let newBhnmURL = json["bhnm_url"] as? String, !newBhnmURL.isEmpty {
                bhnmURL = newBhnmURL
                middlewareURL = str("middleware_url")
            } else if let oldServer = json["server"] as? String, !oldServer.isEmpty {
                // Old format: "server" held the middleware URL; bhnmURL is unknown — leave empty
                bhnmURL = ""
                middlewareURL = oldServer
            } else {
                fail("The link is missing a valid server URL.")
                return
            }

            let notificationsEnabled = (json["notifications"] as? Bool) ?? true

            pendingImport = PendingImport(
                bhnmURL:              bhnmURL,
                middlewareURL:        middlewareURL,
                notificationsEnabled: notificationsEnabled,
                apiKey:               str("api_key"),
                pin:                  str("pin"),
                ackUser:              str("user", default: "enter user name"),
                name:                 str("name"),
                pushSecret:           str("push_secret"),
                symbol:               str("symbol", default: "server.rack"),
                accentColor:          str("color", default: "#0A84FF")
            )
        } catch {
            fail("The link is invalid or was created with a different key.")
        }
    }

    private func zlibDecompress(_ data: Data) throws -> Data {
        // Python's zlib.compress produces a zlib stream: 2-byte header + raw DEFLATE + 4-byte Adler-32.
        // Swift's Compression framework (COMPRESSION_ZLIB) expects raw DEFLATE only — strip both wrappers.
        guard data.count > 6 else { throw CryptoError.invalidBase64 }
        let deflateData = data.dropFirst(2).dropLast(4)
        var outputBuffer = [UInt8](repeating: 0, count: data.count * 8)
        let resultSize = deflateData.withUnsafeBytes { src in
            compression_decode_buffer(
                &outputBuffer, outputBuffer.count,
                src.baseAddress!.assumingMemoryBound(to: UInt8.self),
                src.count,
                nil, COMPRESSION_ZLIB
            )
        }
        guard resultSize > 0 else { throw CryptoError.invalidUTF8 }
        return Data(outputBuffer.prefix(resultSize))
    }

    private func decryptToData(_ base64url: String, using key: SymmetricKey) throws -> Data {
        var b64 = base64url
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = b64.count % 4
        if remainder != 0 { b64 += String(repeating: "=", count: 4 - remainder) }
        guard let combined = Data(base64Encoded: b64) else { throw CryptoError.invalidBase64 }
        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(sealedBox, using: key)
    }

    private func decrypt(_ base64url: String, using key: SymmetricKey) throws -> String {
        // Convert base64url → standard base64 with padding
        var b64 = base64url
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = b64.count % 4
        if remainder != 0 { b64 += String(repeating: "=", count: 4 - remainder) }

        guard let combined = Data(base64Encoded: b64) else {
            throw CryptoError.invalidBase64
        }
        // Pass full blob to SealedBox — CryptoKit extracts nonce (12 bytes) and tag (16 bytes) internally
        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        let plaintext  = try AES.GCM.open(sealedBox, using: key)
        guard let string = String(data: plaintext, encoding: .utf8) else {
            throw CryptoError.invalidUTF8
        }
        return string
    }

    private enum CryptoError: Error {
        case invalidKey, invalidBase64, invalidUTF8
    }
}

extension Notification.Name {
    static let deepLinkConnectionApplied = Notification.Name("DeepLinkConnectionApplied")
}
