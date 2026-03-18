import SwiftUI

struct InterfacePerformanceView: View {
    let interface: DeviceInterface
    let deviceName: String
    let netreoService: SimpleNetreoService
    @State private var performanceData: InterfacePerformanceData?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedDataPoint: BandwidthDataPoint?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header info
                VStack(spacing: 8) {
                    HStack {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 16, height: 16)
                        
                        Text(interface.name)
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Spacer()
                        
                        Text(interface.status.capitalized)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(statusColor.opacity(0.15))
                            .foregroundColor(statusColor)
                            .cornerRadius(8)
                    }
                    
                    if !interface.ipAddress.isEmpty {
                        HStack {
                            Text("IP Address: \(interface.ipAddress)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                    
                    if let data = performanceData {
                        HStack {
                            Text(data.timeRange)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                }
                .padding()
                .background(Color(.systemGroupedBackground))
                
                Divider()
                
                // Charts content
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading performance data...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                        
                        Text("Error loading performance data")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Retry") {
                            loadPerformanceData()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let data = performanceData {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Inbound bandwidth chart
                            chartSection(
                                title: "Inbound Bandwidth",
                                data: data.inboundData,
                                color: .blue,
                                icon: "arrow.down.circle.fill"
                            )
                            
                            // Outbound bandwidth chart  
                            chartSection(
                                title: "Outbound Bandwidth",
                                data: data.outboundData,
                                color: .green,
                                icon: "arrow.up.circle.fill"
                            )
                            
                            // Statistics section
                            statisticsSection(data: data)
                        }
                        .padding()
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        
                        Text("No Performance Data")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Performance data is not available for this interface.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Interface Performance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refresh") {
                        loadPerformanceData()
                    }
                    .disabled(isLoading)
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            loadPerformanceData()
        }
    }
    
    @ViewBuilder
    private func chartSection(title: String, data: [BandwidthDataPoint], color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                
                if let maxValue = data.max(by: { $0.value < $1.value }) {
                    Text("Peak: \(maxValue.formattedValue)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            SimpleLineChart(data: data, color: color)
                .frame(height: 200)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private func statisticsSection(data: InterfacePerformanceData) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Statistics")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    statisticCard(
                        title: "Avg Inbound",
                        value: formatBytes(calculateAverage(data.inboundData)),
                        color: .blue,
                        icon: "arrow.down"
                    )
                    
                    statisticCard(
                        title: "Avg Outbound", 
                        value: formatBytes(calculateAverage(data.outboundData)),
                        color: .green,
                        icon: "arrow.up"
                    )
                }
                
                HStack(spacing: 16) {
                    statisticCard(
                        title: "Peak Inbound",
                        value: formatBytes(data.inboundData.max(by: { $0.value < $1.value })?.value ?? 0),
                        color: .blue,
                        icon: "arrow.up.right"
                    )
                    
                    statisticCard(
                        title: "Peak Outbound",
                        value: formatBytes(data.outboundData.max(by: { $0.value < $1.value })?.value ?? 0),
                        color: .green, 
                        icon: "arrow.up.right"
                    )
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private func statisticCard(title: String, value: String, color: Color, icon: String) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground))
        .cornerRadius(8)
    }
    
    private var statusColor: Color {
        switch interface.statusColor {
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
    
    private func formatBytes(_ bytes: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes)) + "/s"
    }
    
    private func calculateAverage(_ data: [BandwidthDataPoint]) -> Double {
        guard !data.isEmpty else { return 0.0 }
        let sum = data.map(\.value).reduce(0, +)
        return sum / Double(data.count)
    }
    
    private func loadPerformanceData() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let data = try await netreoService.fetchInterfacePerformance(
                    deviceName: deviceName,
                    interfaceName: interface.name
                )
                DispatchQueue.main.async {
                    self.performanceData = data
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}

#Preview {
    InterfacePerformanceView(
        interface: DeviceInterface(
            name: "GigabitEthernet0/0",
            status: "up",
            interfaceType: "ethernet",
            speed: "1000 Mbps",
            ipAddress: "192.168.1.1"
        ),
        deviceName: "Router",
        netreoService: SimpleNetreoService(baseURL: "http://example.com", apiKey: "test")
    )
}

struct SimpleLineChart: View {
    let data: [BandwidthDataPoint]
    let color: Color
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let maxValue = data.max(by: { $0.value < $1.value })?.value ?? 1
            let minValue = data.min(by: { $0.value < $1.value })?.value ?? 0
            let valueRange = maxValue - minValue
            
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.tertiarySystemFill))
                
                // Grid lines
                VStack {
                    ForEach(0..<5) { i in
                        Rectangle()
                            .fill(Color(.separator))
                            .frame(height: 0.5)
                            .opacity(0.3)
                        if i < 4 { Spacer() }
                    }
                }
                .padding(.horizontal, 20)
                
                // Chart line
                if data.count > 1 {
                    Path { path in
                        let points = data.enumerated().map { index, point in
                            let x = width * CGFloat(index) / CGFloat(data.count - 1)
                            let normalizedValue = valueRange > 0 ? (point.value - minValue) / valueRange : 0.5
                            let y = height * (1 - normalizedValue)
                            return CGPoint(x: x, y: y)
                        }
                        
                        if let firstPoint = points.first {
                            path.move(to: firstPoint)
                            for point in points.dropFirst() {
                                path.addLine(to: point)
                            }
                        }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    
                    // Area fill
                    Path { path in
                        let points = data.enumerated().map { index, point in
                            let x = width * CGFloat(index) / CGFloat(data.count - 1)
                            let normalizedValue = valueRange > 0 ? (point.value - minValue) / valueRange : 0.5
                            let y = height * (1 - normalizedValue)
                            return CGPoint(x: x, y: y)
                        }
                        
                        if let firstPoint = points.first {
                            path.move(to: CGPoint(x: firstPoint.x, y: height))
                            path.addLine(to: firstPoint)
                            for point in points.dropFirst() {
                                path.addLine(to: point)
                            }
                            if let lastPoint = points.last {
                                path.addLine(to: CGPoint(x: lastPoint.x, y: height))
                            }
                            path.closeSubpath()
                        }
                    }
                    .fill(color.opacity(0.2))
                }
                
                // Value labels
                VStack {
                    HStack {
                        Text(formatBytes(maxValue))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    Spacer()
                    HStack {
                        Text(formatBytes(minValue))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                
                // Time labels
                VStack {
                    Spacer()
                    HStack {
                        if let firstPoint = data.first {
                            Text(formatTime(firstPoint.timestamp))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if let lastPoint = data.last {
                            Text(formatTime(lastPoint.timestamp))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
    }
    
    private func formatBytes(_ bytes: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes)) + "/s"
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
