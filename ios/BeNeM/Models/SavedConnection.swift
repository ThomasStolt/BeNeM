// BeNeM/Models/SavedConnection.swift
import Foundation

struct SavedConnection: Codable, Identifiable {
    let id: UUID
    var name: String
    var middlewareURL: String    // previously "baseURL"; proxy + APNs registration endpoint
    var bhnmURL: String         // direct BHNM server URL; sent as X-BHNM-Target
    var notificationsEnabled: Bool
    var apiKey: String
    var pin: String             // "" = absent
    var ackUser: String         // "" = absent
    var webhookSecret: String
    var symbol: String
    var accentColor: String

    // MARK: - Memberwise init (notificationsEnabled defaults true for new connections)
    init(
        id: UUID = UUID(),
        name: String,
        middlewareURL: String = "",
        bhnmURL: String,
        notificationsEnabled: Bool = true,
        apiKey: String,
        pin: String = "",
        ackUser: String = "",
        webhookSecret: String = "",
        symbol: String = "server.rack",
        accentColor: String = "#0A84FF"
    ) {
        self.id = id
        self.name = name
        self.middlewareURL = middlewareURL
        self.bhnmURL = bhnmURL
        self.notificationsEnabled = notificationsEnabled
        self.apiKey = apiKey
        self.pin = pin
        self.ackUser = ackUser
        self.webhookSecret = webhookSecret
        self.symbol = symbol
        self.accentColor = accentColor
    }

    // MARK: - Codable: maps "baseURL" JSON key → middlewareURL field; defaults for new fields
    enum CodingKeys: String, CodingKey {
        case id, name, apiKey, pin, ackUser, webhookSecret, symbol, accentColor
        case middlewareURL = "baseURL"   // backward compat: existing JSON uses "baseURL"
        case bhnmURL
        case notificationsEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                   = try c.decode(UUID.self,   forKey: .id)
        name                 = try c.decode(String.self, forKey: .name)
        middlewareURL        = try c.decode(String.self, forKey: .middlewareURL)
        bhnmURL              = try c.decodeIfPresent(String.self, forKey: .bhnmURL)              ?? ""
        // Migration default: false — bhnmURL is empty so push registration would be incomplete
        notificationsEnabled = try c.decodeIfPresent(Bool.self,   forKey: .notificationsEnabled) ?? false
        apiKey               = try c.decode(String.self, forKey: .apiKey)
        pin                  = try c.decodeIfPresent(String.self, forKey: .pin)                  ?? ""
        ackUser              = try c.decodeIfPresent(String.self, forKey: .ackUser)              ?? ""
        webhookSecret        = try c.decodeIfPresent(String.self, forKey: .webhookSecret)        ?? ""
        symbol               = try c.decodeIfPresent(String.self, forKey: .symbol)               ?? "server.rack"
        accentColor          = try c.decodeIfPresent(String.self, forKey: .accentColor)          ?? "#0A84FF"
    }
}

// MARK: - Keychain-backed sensitive fields

extension SavedConnection {
    /// Move sensitive fields to Keychain, keyed by connection UUID.
    func saveToKeychain() {
        let prefix = id.uuidString
        KeychainHelper.save(key: "\(prefix).apiKey", value: apiKey)
        KeychainHelper.save(key: "\(prefix).pin", value: pin)
        KeychainHelper.save(key: "\(prefix).webhookSecret", value: webhookSecret)
    }

    /// Load sensitive fields from Keychain, falling back to the struct's own values
    /// (which covers migration from pre-Keychain versions).
    mutating func loadFromKeychain() {
        let prefix = id.uuidString
        if let k = KeychainHelper.load(key: "\(prefix).apiKey") { apiKey = k }
        if let p = KeychainHelper.load(key: "\(prefix).pin") { pin = p }
        if let w = KeychainHelper.load(key: "\(prefix).webhookSecret") { webhookSecret = w }
    }

    /// Remove Keychain entries for this connection.
    func deleteFromKeychain() {
        let prefix = id.uuidString
        KeychainHelper.delete(key: "\(prefix).apiKey")
        KeychainHelper.delete(key: "\(prefix).pin")
        KeychainHelper.delete(key: "\(prefix).webhookSecret")
    }
}

extension UserDefaults {
    private static let savedConnectionsKey = "saved_connections"

    func loadSavedConnections() -> [SavedConnection] {
        guard let data = data(forKey: Self.savedConnectionsKey) else { return [] }
        var connections = (try? JSONDecoder().decode([SavedConnection].self, from: data)) ?? []
        for i in connections.indices {
            connections[i].loadFromKeychain()
        }
        return connections
    }

    func saveSavedConnections(_ connections: [SavedConnection]) {
        // Store sensitive fields in Keychain
        for connection in connections {
            connection.saveToKeychain()
        }
        guard let data = try? JSONEncoder().encode(connections) else { return }
        set(data, forKey: Self.savedConnectionsKey)
    }
}
