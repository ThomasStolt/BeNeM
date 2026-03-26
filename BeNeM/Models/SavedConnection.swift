// BeNeM/Models/SavedConnection.swift
import Foundation

struct SavedConnection: Codable, Identifiable {
    let id: UUID
    var name: String
    var baseURL: String
    var apiKey: String
    var pin: String      // "" = absent
    var ackUser: String  // "" = absent
    var webhookSecret: String = ""  // "" = push notifications disabled for this server
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
