import CryptoKit
import Foundation

@MainActor
final class DeepLinkHandler: ObservableObject {

    struct PendingImport {
        let serverURL: String
        let apiKey: String
        let pin: String       // "" if absent
        let ackUser: String
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

        guard let server = param("server"), !server.isEmpty,
              let encryptedKey = param("api_key"), !encryptedKey.isEmpty else {
            fail("The link is missing required fields.")
            return
        }

        guard server.hasPrefix("http://") || server.hasPrefix("https://") else {
            fail("The link contains an invalid server URL.")
            return
        }

        let encryptedPin = param("pin") ?? ""
        let ackUser = param("ack_user") ?? "enter user name"

        do {
            let symmetricKey = try loadKey()
            let decryptedKey = try decrypt(encryptedKey, using: symmetricKey)
            let decryptedPin = encryptedPin.isEmpty ? "" : try decrypt(encryptedPin, using: symmetricKey)
            pendingImport = PendingImport(
                serverURL: server,
                apiKey: decryptedKey,
                pin: decryptedPin,
                ackUser: ackUser
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
            // Update credentials in place; preserve id, baseURL, name
            connections[idx].apiKey  = imp.apiKey
            connections[idx].pin     = imp.pin
            connections[idx].ackUser = imp.ackUser
            upsertedID = connections[idx].id
        } else {
            // New entry — derive display name from hostname
            let name = URL(string: imp.serverURL)?.host ?? imp.serverURL
            let newConn = SavedConnection(
                id: UUID(),
                name: name,
                baseURL: imp.serverURL,
                apiKey: imp.apiKey,
                pin: imp.pin,
                ackUser: imp.ackUser
            )
            connections.append(newConn)
            upsertedID = newConn.id
        }

        ud.saveSavedConnections(connections)

        // 3. Persist active connection ID (same key read by SettingsView @AppStorage)
        ud.set(upsertedID.uuidString, forKey: "netreo_active_connection_id")

        // 4. Clear pending import AFTER all work is done, before notification
        pendingImport = nil

        // 5. Notify SettingsView to reload if visible
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
