import SwiftUI

struct SimpleQuickConfigView: View {
    @Binding var serverIP: String
    @Binding var apiKey: String
    @State private var isTestingConnection = false
    @State private var connectionResult: String?
    @State private var showingAlert = false
    let onConnectionSuccess: (SimpleNetreoService, [SimpleDevice]) -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Quick Setup")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                TextField("Netreo Server IP (e.g., 192.168.2.211)", text: $serverIP)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .keyboardType(.URL)
                
                SecureField("API Key", text: $apiKey)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
            }
            
            Button("Log In") {
                testConnection()
            }
            .buttonStyle(.borderedProminent)
            .disabled(serverIP.isEmpty || apiKey.isEmpty || isTestingConnection)
            
            if isTestingConnection {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Logging in...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Text("Enter your Netreo server IP address and API key to get started.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
        .alert("Login Result", isPresented: $showingAlert) {
            Button("OK") {
                connectionResult = nil
            }
        } message: {
            Text(connectionResult ?? "")
        }
    }
    
    private func testConnection() {
        isTestingConnection = true
        connectionResult = nil
        
        Task {
            do {
                let service = SimpleNetreoService(baseURL: formatURL(serverIP), apiKey: apiKey)
                let devices = try await service.testConnection()
                
                await MainActor.run {
                    isTestingConnection = false
                    connectionResult = "✅ Login successful!\nFound \(devices.count) devices."
                    showingAlert = true
                    
                    // Call the success callback to switch to device list
                    onConnectionSuccess(service, devices)
                }
            } catch {
                await MainActor.run {
                    isTestingConnection = false
                    let errorMessage = if let netreoError = error as? NetreoError {
                        netreoError.errorDescription ?? error.localizedDescription
                    } else {
                        error.localizedDescription
                    }
                    connectionResult = "❌ Login failed:\n\(errorMessage)\n\nTroubleshooting:\n• Verify IP: \(serverIP)\n• Check if API key is correct\n• Try username/password instead of API key\n• Ensure server is reachable\n• Check if API endpoints are enabled"
                    showingAlert = true
                }
            }
        }
    }
    
    private func formatURL(_ url: String) -> String {
        var formatted = url.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !formatted.hasPrefix("http://") && !formatted.hasPrefix("https://") {
            formatted = "http://\(formatted)"
        }
        
        return formatted
    }
}

#Preview {
    SimpleQuickConfigView(
        serverIP: .constant("192.168.2.211"),
        apiKey: .constant("ThisIsAPassword"),
        onConnectionSuccess: { _, _ in }
    )
}