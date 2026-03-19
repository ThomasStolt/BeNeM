import SwiftUI

struct AutoDiscoveryView: View {
    @StateObject private var discovery = NetworkDiscovery()
    @AppStorage("netreo_base_url") private var baseURL = ""
    @State private var connectingServer: DiscoveredServer?
    @State private var apiKeyInput = ""
    @State private var showConnectSheet = false
    @State private var showSuccessBanner = false

    var body: some View {
        Form {
            // Info / scan button
            Section {
                if let error = discovery.errorMessage {
                    Label(error, systemImage: "wifi.slash")
                        .foregroundColor(.orange)
                        .font(.subheadline)
                } else {
                    Label("Scans your local Wi-Fi (/24) for Netreo servers via SNMP.", systemImage: "info.circle")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Button(action: { Task { await discovery.scan() } }) {
                    HStack {
                        if discovery.isScanning {
                            ProgressView().padding(.trailing, 4)
                            Text("Scanning…")
                        } else {
                            Image(systemName: "magnifyingglass")
                            Text(discovery.servers.isEmpty ? "Start Discovery" : "Scan Again")
                        }
                    }
                }
                .disabled(discovery.isScanning)

                if discovery.isScanning {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: discovery.progress)
                        Text("\(discovery.scannedCount) / \(discovery.totalCount) hosts checked")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }

            // Results
            if !discovery.servers.isEmpty {
                Section(header: Text("Found Netreo Servers")) {
                    ForEach(discovery.servers) { server in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(server.ip)
                                .font(.headline)
                            Text(server.sysDescr)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 2)
                        .swipeActions {
                            Button("Connect") {
                                connectingServer = server
                                apiKeyInput = ""
                                showConnectSheet = true
                            }
                            .tint(.blue)
                        }
                        .onTapGesture {
                            connectingServer = server
                            apiKeyInput = ""
                            showConnectSheet = true
                        }
                    }
                }
            } else if !discovery.isScanning && discovery.errorMessage == nil && discovery.scannedCount > 0 {
                Section {
                    Label("No Netreo servers found on this network.", systemImage: "questionmark.circle")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Auto Discovery")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showConnectSheet) {
            connectSheet
        }
        .overlay(alignment: .top) {
            if showSuccessBanner {
                Text("Server configured — enter your API key in Settings.")
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: showSuccessBanner)
    }

    // MARK: Connect sheet

    private var connectSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("Server")) {
                    if let server = connectingServer {
                        Text(server.ip).foregroundColor(.secondary)
                        Text(server.sysDescr)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                    }
                }
                Section(header: Text("API Key"), footer: Text("Your Netreo API key. You can also set it later in Settings.")) {
                    SecureField("API Key (optional)", text: $apiKeyInput)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Connect to Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { showConnectSheet = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Connect") {
                        if let server = connectingServer {
                            baseURL = server.baseURL
                            if !apiKeyInput.isEmpty {
                                UserDefaults.standard.set(apiKeyInput, forKey: "netreo_api_key")
                            }
                        }
                        showConnectSheet = false
                        withAnimation { showSuccessBanner = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation { showSuccessBanner = false }
                        }
                    }
                }
            }
        }
    }
}
