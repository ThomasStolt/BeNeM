import SwiftUI

struct DeviceListView: View {
    @StateObject private var viewModel: DeviceListViewModel
    @State private var showingAddDevice = false
    @State private var connectionStatus: ConnectionStatus = .unknown
    @AppStorage("refresh_interval") private var refreshInterval: Double = 120.0
    @AppStorage("maxDevicesCount") private var maxDevicesCount: Int = 20
    private let apiService: NetreoAPIService

    init(apiService: NetreoAPIService) {
        self.apiService = apiService
        _viewModel = StateObject(wrappedValue: DeviceListViewModel(apiService: apiService))
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(viewModel.devices) { device in
                    NavigationLink(destination: DeviceDetailView(device: device, apiService: apiService)) {
                        DeviceRowView(device: device)
                    }
                }
                if viewModel.hasMore {
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
                }
            }
            .navigationTitle("Devices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    ConnectionBadgeButton(status: connectionStatus) {
                        Task { await viewModel.loadDevices(limit: maxDevicesCount) }
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button("Add") { showingAddDevice = true }
                    AutoRefreshButton(
                        interval: refreshInterval,
                        isLoading: viewModel.isLoading,
                        action: { await viewModel.loadDevices(limit: maxDevicesCount) }
                    )
                }
            }
            .sheet(isPresented: $showingAddDevice) {
                AddDeviceView(viewModel: viewModel)
            }
            .refreshable { await viewModel.loadDevices(limit: maxDevicesCount) }
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
            .onChange(of: maxDevicesCount) { newLimit in
                Task { await viewModel.loadDevices(limit: newLimit) }
            }
            .task(id: connectionStatus) {
                guard connectionStatus == .disconnected else { return }
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled, connectionStatus == .disconnected else { return }
                Task { await viewModel.loadDevices(limit: maxDevicesCount) }
            }
        }
        .task {
            guard viewModel.devices.isEmpty && viewModel.errorMessage == nil else { return }
            await viewModel.loadDevices(limit: maxDevicesCount)
        }
        .onChange(of: ObjectIdentifier(apiService)) { _, _ in
            viewModel.updateAPIService(apiService)
        }
    }
}

struct DeviceRowView: View {
    let device: NetreoDevice
    
    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
            
            VStack(alignment: .leading) {
                Text(device.name ?? device.ip)
                    .font(.headline)
                Text(device.ip)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(device.status.rawValue.capitalized)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.2))
                .cornerRadius(8)
        }
        .padding(.vertical, 2)
    }
    
    private var statusColor: Color {
        switch device.status {
        case .up:
            return .green
        case .down:
            return .red
        case .warning:
            return .orange
        case .critical:
            return .red
        case .maintenance:
            return .blue
        case .unknown:
            return .gray
        }
    }
}