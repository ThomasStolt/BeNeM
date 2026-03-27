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

extension UserDefaults {
    private static let savedConnectionsKey = "saved_connections"

    func loadSavedConnections() -> [SavedConnection] {
        guard let data = data(forKey: Self.savedConnectionsKey) else { return [] }
        return (try? JSONDecoder().decode([SavedConnection].self, from: data)) ?? []
    }

    func saveSavedConnections(_ connections: [SavedConnection]) {
        guard let data = try? JSONEncoder().encode(connections) else { return }
        set(data, forKey: Self.savedConnectionsKey)
    }
}
