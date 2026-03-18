import SwiftUI

struct DashboardView: View {
    @StateObject private var incidentViewModel: IncidentListViewModel
    @StateObject private var deviceViewModel: DeviceListViewModel
    @State private var selectedIncident: NetreoIncident?
    @State private var selectedDevice: NetreoDevice?
    
    private let apiService: NetreoAPIService
    
    init(apiService: NetreoAPIService) {
        self.apiService = apiService
        self._incidentViewModel = StateObject(wrappedValue: IncidentListViewModel(apiService: apiService))
        self._deviceViewModel = StateObject(wrappedValue: DeviceListViewModel(apiService: apiService))
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    
                    pullDownsSection
                    
                    if incidentViewModel.isLoading || deviceViewModel.isLoading {
                        ProgressView("Loading...")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else {
                        contentSection
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .refreshable {
                await loadData()
            }
            .task {
                await loadData()
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Network Status")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("BeNeM Monitoring Dashboard")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { Task { await loadData() } }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.title2)
                        .foregroundColor(.primary)
                }
                .disabled(incidentViewModel.isLoading || deviceViewModel.isLoading)
            }
            
            HStack(spacing: 20) {
                StatusCard(
                    title: "Active Incidents",
                    count: incidentViewModel.activeIncidentsCount,
                    color: incidentViewModel.criticalIncidentsCount > 0 ? .red : .orange,
                    icon: "exclamationmark.triangle.fill"
                )
                
                StatusCard(
                    title: "Total Devices",
                    count: deviceViewModel.devices.count,
                    color: .blue,
                    icon: "network"
                )
            }
        }
    }
    
    private var pullDownsSection: some View {
        VStack(spacing: 16) {
            Text("Quick Access")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: 12) {
                Menu {
                    ForEach(incidentViewModel.incidents.prefix(10)) { incident in
                        Button(action: { selectedIncident = incident }) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(incident.summary)
                                        .lineLimit(1)
                                    Text(incident.deviceName ?? "Unknown Device")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } icon: {
                                Circle()
                                    .fill(incidentSeverityColor(incident.severity))
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }
                    
                    if incidentViewModel.incidents.isEmpty {
                        Text("No incidents")
                            .foregroundColor(.secondary)
                    }
                } label: {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Select Incident")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            if let incident = selectedIncident {
                                Text(incident.summary)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            } else {
                                Text("\(incidentViewModel.incidents.count) incidents available")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.down")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                }
                
                Menu {
                    ForEach(deviceViewModel.devices) { device in
                        Button(action: { selectedDevice = device }) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name ?? device.ip)
                                        .lineLimit(1)
                                    Text(device.ip)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } icon: {
                                Circle()
                                    .fill(deviceStatusColor(device.status))
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }
                    
                    if deviceViewModel.devices.isEmpty {
                        Text("No devices")
                            .foregroundColor(.secondary)
                    }
                } label: {
                    HStack {
                        Image(systemName: "network")
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Select Device")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            if let device = selectedDevice {
                                Text(device.name ?? device.ip)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            } else {
                                Text("\(deviceViewModel.devices.count) devices available")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.down")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                }
            }
        }
    }
    
    private var contentSection: some View {
        VStack(spacing: 20) {
            if let incident = selectedIncident {
                IncidentDetailCard(incident: incident)
            }
            
            if let device = selectedDevice {
                DeviceDetailCard(device: device)
            }
            
            if selectedIncident == nil && selectedDevice == nil {
                VStack(spacing: 16) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    
                    Text("Select an incident or device above to view details")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 40)
            }
        }
    }
    
    private func loadData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await incidentViewModel.loadIncidents()
            }
            group.addTask {
                await deviceViewModel.loadDevices()
            }
        }
    }
    
    private func incidentSeverityColor(_ severity: NetreoIncident.IncidentSeverity) -> Color {
        switch severity {
        case .critical:
            return .red
        case .major:
            return .orange
        case .minor, .warning:
            return .yellow
        case .informational:
            return .blue
        }
    }
    
    private func deviceStatusColor(_ status: NetreoDevice.DeviceStatus) -> Color {
        switch status {
        case .up:
            return .green
        case .down:
            return .red
        case .warning:
            return .yellow
        case .critical:
            return .red
        case .maintenance:
            return .blue
        case .unknown:
            return .gray
        }
    }
}

struct StatusCard: View {
    let title: String
    let count: Int
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title2)
                
                Spacer()
                
                Text("\(count)")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(color)
            }
            
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

struct IncidentDetailCard: View {
    let incident: NetreoIncident
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Incident Details")
                    .font(.headline)
                
                Spacer()
                
                Text(incident.severity.rawValue.capitalized)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(severityColor.opacity(0.2))
                    .foregroundColor(severityColor)
                    .clipShape(Capsule())
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(incident.summary)
                    .font(.title3)
                    .fontWeight(.semibold)
                
                if let description = incident.description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                if let deviceName = incident.deviceName {
                    HStack {
                        Image(systemName: "network")
                            .foregroundColor(.secondary)
                        
                        Text(deviceName)
                            .font(.subheadline)
                        
                        if let deviceIP = incident.deviceIP {
                            Text("(\(deviceIP))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                HStack {
                    Text("Started: \(incident.startTime, style: .relative) ago")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if incident.status == .acknowledged {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                            
                            Text("Acknowledged")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
    
    private var severityColor: Color {
        switch incident.severity {
        case .critical:
            return .red
        case .major:
            return .orange
        case .minor, .warning:
            return .yellow
        case .informational:
            return .blue
        }
    }
}

struct DeviceDetailCard: View {
    let device: NetreoDevice
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Device Details")
                    .font(.headline)
                
                Spacer()
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    
                    Text(device.status.rawValue.capitalized)
                        .font(.caption)
                        .foregroundColor(statusColor)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(device.name ?? device.ip)
                    .font(.title3)
                    .fontWeight(.semibold)
                
                HStack {
                    Text("IP:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(device.ip)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                if let hostname = device.hostname {
                    HStack {
                        Text("Hostname:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(hostname)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
                
                if let deviceType = device.deviceType {
                    HStack {
                        Text("Type:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(deviceType.capitalized)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
                
                Text("Last Updated: \(device.lastUpdated, style: .relative) ago")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
    
    private var statusColor: Color {
        switch device.status {
        case .up:
            return .green
        case .down:
            return .red
        case .warning:
            return .yellow
        case .critical:
            return .red
        case .maintenance:
            return .blue
        case .unknown:
            return .gray
        }
    }
}

#Preview {
    DashboardView(apiService: NetreoAPIService(baseURL: "http://demo.netreo.com", apiKey: "test"))
}