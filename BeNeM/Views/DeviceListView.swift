import SwiftUI

struct DeviceListView: View {
    @StateObject private var viewModel: DeviceListViewModel
    @State private var showingAddDevice = false
    
    init(apiService: NetreoAPIService) {
        _viewModel = StateObject(wrappedValue: DeviceListViewModel(apiService: apiService))
    }
    
    var body: some View {
        NavigationView {
            List {
                ForEach(viewModel.devices) { device in
                    DeviceRowView(device: device)
                }
                .onDelete { indexSet in
                    Task {
                        for index in indexSet {
                            await viewModel.deleteDevice(viewModel.devices[index])
                        }
                    }
                }
            }
            .navigationTitle("Devices")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        showingAddDevice = true
                    }
                }
            }
            .sheet(isPresented: $showingAddDevice) {
                AddDeviceView(viewModel: viewModel)
            }
            .refreshable {
                await viewModel.loadDevices()
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView("Loading devices...")
                }
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .task {
            await viewModel.loadDevices()
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