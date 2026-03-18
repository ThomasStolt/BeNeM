import SwiftUI

struct DeviceLatencyView: View {
    let device: SimpleDevice
    let netreoService: SimpleNetreoService
    @State private var latencyData: LatencyData?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header info
                VStack(spacing: 8) {
                    HStack {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 16, height: 16)
                        
                        Text(device.name)
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Spacer()
                        
                        Text("Latency")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .cornerRadius(8)
                    }
                    
                    HStack {
                        Text("IP: \(device.ip)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    
                    if let data = latencyData {
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
                
                // Content
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading latency data...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                        
                        Text("Error loading latency data")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Retry") {
                            loadLatencyData()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let data = latencyData {
                    if data.dataPoints.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "wifi.slash")
                                .font(.system(size: 50))
                                .foregroundColor(.secondary)
                            
                            Text("No Latency Data")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text("No data available")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(spacing: 24) {
                                // Latency chart
                                latencyChartSection(data: data)
                                
                                // Statistics section
                                latencyStatisticsSection(data: data)
                            }
                            .padding()
                        }
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        
                        Text("No Latency Data")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Latency data is not available for this device.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Device Latency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refresh") {
                        loadLatencyData()
                    }
                    .disabled(isLoading)
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            loadLatencyData()
        }
    }
    
    @ViewBuilder
    private func latencyChartSection(data: LatencyData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "wifi")
                    .foregroundColor(.blue)
                Text("Ping Latency")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                
                if let maxValue = data.dataPoints.max(by: { $0.latencyMs < $1.latencyMs }) {
                    Text("Peak: \(maxValue.formattedLatency)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            LatencyLineChart(data: data.dataPoints)
                .frame(height: 200)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private func latencyStatisticsSection(data: LatencyData) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Statistics")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    latencyStatisticCard(
                        title: "Average",
                        value: formatLatency(data.averageLatency),
                        color: .blue,
                        icon: "minus"
                    )
                    
                    latencyStatisticCard(
                        title: "Minimum", 
                        value: formatLatency(data.minLatency),
                        color: .green,
                        icon: "arrow.down.to.line"
                    )
                }
                
                HStack(spacing: 16) {
                    latencyStatisticCard(
                        title: "Maximum",
                        value: formatLatency(data.maxLatency),
                        color: .red,
                        icon: "arrow.up.to.line"
                    )
                    
                    latencyStatisticCard(
                        title: "Data Points",
                        value: "\(data.dataPoints.count)",
                        color: .purple,
                        icon: "chart.dots.scatter"
                    )
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private func latencyStatisticCard(title: String, value: String, color: Color, icon: String) -> some View {
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
    
    private func formatLatency(_ latency: Double) -> String {
        if latency >= 1000 {
            return String(format: "%.1f s", latency / 1000)
        } else {
            return String(format: "%.1f ms", latency)
        }
    }
    
    private func loadLatencyData() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let data = try await netreoService.fetchDeviceLatency(deviceName: device.name)
                DispatchQueue.main.async {
                    self.latencyData = data
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

struct LatencyLineChart: View {
    let data: [LatencyDataPoint]
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let maxValue = data.max(by: { $0.latencyMs < $1.latencyMs })?.latencyMs ?? 1
            let minValue = data.min(by: { $0.latencyMs < $1.latencyMs })?.latencyMs ?? 0
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
                            let normalizedValue = valueRange > 0 ? (point.latencyMs - minValue) / valueRange : 0.5
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
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    
                    // Area fill
                    Path { path in
                        let points = data.enumerated().map { index, point in
                            let x = width * CGFloat(index) / CGFloat(data.count - 1)
                            let normalizedValue = valueRange > 0 ? (point.latencyMs - minValue) / valueRange : 0.5
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
                    .fill(Color.blue.opacity(0.2))
                }
                
                // Value labels
                VStack {
                    HStack {
                        Text(formatLatency(maxValue))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    Spacer()
                    HStack {
                        Text(formatLatency(minValue))
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
    
    private func formatLatency(_ latency: Double) -> String {
        if latency >= 1000 {
            return String(format: "%.1f s", latency / 1000)
        } else {
            return String(format: "%.0f ms", latency)
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

#Preview {
    DeviceLatencyView(
        device: SimpleDevice(ip: "192.168.1.1", name: "Test Router", status: "up", deviceType: "router"),
        netreoService: SimpleNetreoService(baseURL: "http://example.com", apiKey: "test")
    )
}