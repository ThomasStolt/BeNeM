// BeNeM/Models/SavedConnection.swift
import Foundation

struct SavedConnection: Codable, Identifiable {
    let id: UUID
    var name: String
    var baseURL: String
    var apiKey: String
    var pin: String      // "" = absent
    var ackUser: String  // "" = absent
    var webhookSecret: String = ""
    var symbol: String = "server.rack" // SF Symbol name for list icon
    var accentColor: String = "#0A84FF" // hex accent color for icon background
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
