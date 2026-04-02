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
                        Text("Devices")
                            .font(.system(size: 18, weight: .bold, design: .default))
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
            .task(id: connectionStatus) {
                guard connectionStatus == .disconnected else { return }
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled, connectionStatus == .disconnected else { return }
                Task { await viewModel.loadDevices() }
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
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
            
            VStack(alignment: .leading) {
                Text(device.name)
                    .font(.headline)
                HStack(spacing: 4) {
                    Text(device.ip)
                    Text("·").foregroundColor(.secondary)
                    Text(device.category)
                }
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