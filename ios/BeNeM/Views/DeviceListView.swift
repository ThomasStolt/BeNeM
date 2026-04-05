import SwiftUI

struct DeviceListView: View {
    @StateObject private var viewModel: DeviceListViewModel
    @State private var connectionStatus: ConnectionStatus = .unknown
    @AppStorage("refresh_interval") private var refreshInterval: Double = 120.0
    private let apiService: NetreoAPIService

    init(apiService: NetreoAPIService) {
        self.apiService = apiService
        _viewModel = StateObject(wrappedValue: DeviceListViewModel(apiService: apiService))
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(viewModel.displayedDevices) { device in
                    NavigationLink(destination: DeviceDetailView(device: device, apiService: apiService)) {
                        DeviceRowView(device: device)
                    }
                }

                if !viewModel.searchQuery.isEmpty && viewModel.searchQuery.count >= 2 {
                    // Search mode — no pagination
                    if viewModel.isSearching {
                        HStack { Spacer(); ProgressView(); Spacer() }
                            .listRowSeparator(.hidden)
                    } else if viewModel.searchResults.isEmpty {
                        Text("No devices found")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .listRowSeparator(.hidden)
                    }
                } else if viewModel.hasMore {
                    // Browse mode — load more
                    HStack {
                        Spacer()
                        if viewModel.isLoadingMore {
                            ProgressView()
                        } else {
                            Button("Load more") {
                                Task { await viewModel.loadMoreDevices() }
                            }
                        }
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                    .onAppear {
                        Task { await viewModel.loadMoreDevices() }
                    }
                }
            }
            .searchable(text: $viewModel.searchQuery, prompt: "Search devices...")
            .onChange(of: viewModel.searchQuery) { query in
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
                    guard viewModel.searchQuery == query else { return }
                    await viewModel.search(query: query)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    ConnectionBadgeButton(status: connectionStatus) {
                        Task { await viewModel.loadDevices() }
                    }
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image("BMCHelixLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                        if viewModel.totalRecords > 0 {
                            Text("Devices (\(viewModel.totalRecords))")
                                .font(.system(size: 18, weight: .bold))
                        } else {
                            Text("Devices")
                                .font(.system(size: 18, weight: .bold))
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    AutoRefreshButton(
                        interval: refreshInterval,
                        isLoading: viewModel.isLoading,
                        action: { await viewModel.loadDevices() }
                    )
                }
            }
            .refreshable { await viewModel.loadDevices() }
            .overlay {
                if viewModel.isLoading && viewModel.devices.isEmpty {
                    ProgressView("Loading devices...")
                }
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .onChange(of: viewModel.isLoading) { loading in
                guard !loading else { return }
                connectionStatus = viewModel.errorMessage == nil ? .connected : .disconnected
            }
        }
        .task {
            guard viewModel.devices.isEmpty && viewModel.errorMessage == nil else { return }
            await viewModel.loadDevices()
        }
        .onChange(of: ObjectIdentifier(apiService)) { _, _ in
            viewModel.updateAPIService(apiService)
        }
    }
}

struct DeviceRowView: View {
    let device: NetreoDevice

    var body: some View {
        HStack(spacing: 12) {
            DeviceTypeIcon(typeClass: device.typeClass, size: 36, color: statusColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.headline)
                HStack(spacing: 4) {
                    Text(device.ip)
                    Text("·")
                    Text(device.category)
                    Text("·")
                    Text(device.site)
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch device.status {
        case .up:          return .green
        case .down:        return .red
        case .warning:     return .orange
        case .critical:    return .red
        case .maintenance: return .blue
        case .unknown:     return .gray
        }
    }
}
