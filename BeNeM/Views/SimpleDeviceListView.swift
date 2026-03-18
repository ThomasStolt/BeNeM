import SwiftUI

struct SimpleDeviceListView: View {
    let devices: [SimpleDevice]
    let netreoService: SimpleNetreoService?
    @State private var isRefreshing = false
    let onRefresh: () async -> Void
    
    var body: some View {
        NavigationView {
            List {
                ForEach(devices) { device in
                    if let service = netreoService {
                        NavigationLink(destination: DeviceInterfacesView()) {
                            SimpleDeviceRowView(device: device)
                        }
                        .listRowSeparator(.visible)
                    } else {
                        SimpleDeviceRowView(device: device)
                            .listRowSeparator(.visible)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Network Devices (\(devices.count))")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await onRefresh()
            }
            .overlay {
                if devices.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "network.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        
                        Text("No Devices Found")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Pull down to refresh or check your Netreo server connection.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

struct SimpleDeviceRowView: View {
    let device: SimpleDevice
    
    var body: some View {
        HStack(spacing: 12) {
            // Status indicator circle
            Circle()
                .fill(statusColor)
                .frame(width: 14, height: 14)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                Text(device.ip)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if !device.deviceType.isEmpty && device.deviceType != "device" {
                    Text(device.deviceType.capitalized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray5))
                        .cornerRadius(4)
                }
            }
            
            Spacer()
            
            // Status badge
            Text(device.status.capitalized)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(statusColor.opacity(0.15))
                .foregroundColor(statusColor)
                .cornerRadius(12)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }
    
    private var statusColor: Color {
        switch device.statusColor {
        case "green":
            return .green
        case "red":
            return .red
        case "orange":
            return .orange
        case "yellow":
            return .yellow
        case "blue":
            return .blue
        case "purple":
            return .purple
        default:
            return .gray
        }
    }
}

#Preview {
    SimpleDeviceListView(
        devices: [
            SimpleDevice(ip: "192.168.1.1", name: "Router", status: "up", deviceType: "router"),
            SimpleDevice(ip: "192.168.1.10", name: "Switch", status: "up", deviceType: "switch"),
            SimpleDevice(ip: "192.168.1.100", name: "Server", status: "warning", deviceType: "server")
        ],
        netreoService: nil,
        onRefresh: {}
    )
}