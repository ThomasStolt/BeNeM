import Compression
import CryptoKit
import Foundation

@MainActor
final class DeepLinkHandler: ObservableObject {

    struct PendingImport {
        let serverURL: String
        let apiKey: String
        let pin: String               // "" if absent
        let ackUser: String
        let name: String              // "" if absent — falls back to hostname
        let pushMiddlewareURL: String // "" if absent; replaces old pushURL field
        let pushSecret: String        // "" if absent
        let symbol: String            // SF Symbol name; default "server.rack"
        let accentColor: String       // hex colour; default "#0A84FF"
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
        let pushURL         = param("push_url") ?? ""
        let encryptedSecret = param("push_secret") ?? ""

        do {
            let symmetricKey   = try loadKey()
            let decryptedKey    = try decrypt(encryptedKey, using: symmetricKey)
            let decryptedPin    = encryptedPin.isEmpty    ? "" : try decrypt(encryptedPin, using: symmetricKey)
            let decryptedSecret = encryptedSecret.isEmpty ? "" : try decrypt(encryptedSecret, using: symmetricKey)
            pendingImport = PendingImport(
                serverURL:         server,
                apiKey:            decryptedKey,
                pin:               decryptedPin,
                ackUser:           ackUser,
                name:              name,
                pushMiddlewareURL: pushURL,
                pushSecret:        decryptedSecret,
                symbol:            "server.rack",
                accentColor:       "#0A84FF"
            )
        } catch {
            fail("The link is invalid or was created with a different key.")
        }
    }

    func applyPendingImport() {
        guard let imp = pendingImport else { return }

        // 1. Write active AppStorage keys directly to UserDefaults
        let ud = UserDefaults.standard
        ud.set(imp.serverURL, forKey: "netreo_base_url")
        ud.set(imp.apiKey,    forKey: "netreo_api_key")
        ud.set(imp.pin,       forKey: "netreo_pin")
        ud.set(imp.ackUser,   forKey: "netreo_ack_user")

        // 2. Upsert SavedConnection (match by server URL, case-insensitive)
        var connections = ud.loadSavedConnections()
        let serverLower = imp.serverURL.lowercased()
        let upsertedID: UUID

        if let idx = connections.firstIndex(where: { $0.baseURL.lowercased() == serverLower }) {
            // Update credentials in place; update name if provided, otherwise preserve existing
            if !imp.name.isEmpty { connections[idx].name = imp.name }
            connections[idx].apiKey  = imp.apiKey
            connections[idx].pin     = imp.pin
            connections[idx].ackUser = imp.ackUser
            if !imp.pushSecret.isEmpty {
                connections[idx].webhookSecret = imp.pushSecret
            }
            if !imp.pushMiddlewareURL.isEmpty {
                connections[idx].pushMiddlewareURL = imp.pushMiddlewareURL
            }
            connections[idx].symbol      = imp.symbol
            connections[idx].accentColor = imp.accentColor
            upsertedID = connections[idx].id
        } else {
            // New entry — use provided name, or fall back to hostname
            let name = imp.name.isEmpty ? (URL(string: imp.serverURL)?.host ?? imp.serverURL) : imp.name
            let newConn = SavedConnection(
                id: UUID(),
                name: name,
                baseURL: imp.serverURL,
                apiKey: imp.apiKey,
                pin: imp.pin,
                ackUser: imp.ackUser,
                webhookSecret: imp.pushSecret,
                pushMiddlewareURL: imp.pushMiddlewareURL,
                symbol: imp.symbol,
                accentColor: imp.accentColor
            )
            connections.append(newConn)
            upsertedID = newConn.id
        }

        ud.saveSavedConnections(connections)

        // 3. Persist active connection ID (same key read by SettingsView @AppStorage)
        ud.set(upsertedID.uuidString, forKey: "netreo_active_connection_id")

        // 4. Re-register push middleware with the new connection's credentials
        if let token = AppDelegate.shared?.cachedDeviceToken,
           let conn = connections.first(where: { $0.id == upsertedID }) {
            AppDelegate.shared?.registerWithMiddleware(
                token: token,
                secret: conn.webhookSecret,
                middlewareURL: conn.pushMiddlewareURL
            )
        }

        // 5. Clear pending import AFTER all work is done, before notification
        pendingImport = nil

        // 6. Notify SettingsView to reload if visible
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
            guard let server = json["server"] as? String, !server.isEmpty,
                  server.hasPrefix("http://") || server.hasPrefix("https://") else {
                fail("The link is missing a valid server URL.")
                return
            }
            pendingImport = PendingImport(
                serverURL:         server,
                apiKey:            str("api_key"),
                pin:               str("pin"),
                ackUser:           str("user", default: "enter user name"),
                name:              str("name"),
                pushMiddlewareURL: str("push_url"),
                pushSecret:        str("push_secret"),
                symbol:            str("symbol", default: "server.rack"),
                accentColor:       str("color", default: "#0A84FF")
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
