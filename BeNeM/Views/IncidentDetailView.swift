import SwiftUI

private let alwaysShownAlarmColors: [AlarmColor] = [.green, .blue, .yellow, .orange, .red]

struct IncidentDetailView: View {
    let incident: NetreoIncident
    let apiService: NetreoAPIService
    let preloadedAlarmCounts: [AlarmColor: Int]?

    @State private var detail: IncidentDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading details…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(error)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else if let d = detail {
                detailContent(d)
            }
        }
        .navigationTitle("#\(incident.incidentID)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadDetail() }
    }

    // MARK: - Main Content

    @ViewBuilder
    private func detailContent(_ d: IncidentDetail) -> some View {
        List {
            // ── Status Section ──────────────────────────────────────────
            Section {
                HStack(spacing: 12) {
                    StateBadge(label: d.incidentState)
                    Spacer()
                    if let counts = preloadedAlarmCounts {
                        HStack(spacing: 6) {
                            ForEach(alwaysShownAlarmColors, id: \.self) { color in
                                AlarmBadge(label: "\(counts[color] ?? 0)", color: color.color)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // ── Incident Metadata ────────────────────────────────────────
            Section(header: Text("Incident Info")) {
                InfoRow(label: "Incident ID",    value: d.incidentID)
                InfoRow(label: "Title",          value: d.title)
                InfoRow(label: "Device",         value: d.deviceName)
                InfoRow(label: "Alert Type",     value: d.alertType ?? "—")
                if let openTime = d.openTime {
                    InfoRow(label: "Created",    value: formatDate(openTime))
                    InfoRow(label: "Duration",   value: durationString(from: openTime))
                }
                InfoRow(label: "ACK",            value: d.acknowledged ? "Yes" : "No")
                if d.acknowledged {
                    if let t = d.ackTime    { InfoRow(label: "ACK Time",    value: formatDate(t)) }
                    if let u = d.ackUser,  !u.isEmpty  { InfoRow(label: "ACK User",    value: u) }
                    if let c = d.ackComment, !c.isEmpty { InfoRow(label: "ACK Comment", value: c) }
                }
            }

            // ── Primary Alarms ───────────────────────────────────────────
            if !d.primaryAlarms.isEmpty {
                Section(header: Text("Primary Alarms")) {
                    ForEach(d.primaryAlarms) { alarm in
                        AlarmRow(alarm: alarm)
                    }
                }
            }

            // ── Related Alarms ───────────────────────────────────────────
            if !d.relatedAlarms.isEmpty {
                Section(header: Text("Related Alarms")) {
                    ForEach(d.relatedAlarms) { alarm in
                        AlarmRow(alarm: alarm)
                    }
                }
            }

            // ── Incident State Log ───────────────────────────────────────
            if !d.incidentLog.isEmpty {
                Section(header: Text("Incident State Log")) {
                    ForEach(d.incidentLog) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                StateBadge(label: entry.state)
                                Spacer()
                                if let t = entry.time {
                                    Text(formatDate(t))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            if !entry.username.isEmpty {
                                Text(entry.username)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if !entry.comment.isEmpty {
                                Text(entry.comment)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func loadDetail() async {
        isLoading = true
        do {
            detail = try await apiService.fetchIncidentDetail(incidentID: incident.incidentID)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func stateColor(_ state: String) -> Color {
        switch state.uppercased() {
        case "CRITICAL":         return .red
        case "MAJOR":            return .orange
        case "WARNING", "MINOR": return .yellow
        case "OK", "RESOLVED":   return .green
        default:                 return .red
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f.string(from: date)
    }

    private func durationString(from start: Date) -> String {
        let s = Int(Date().timeIntervalSince(start))
        let d = s / 86400; let h = (s % 86400) / 3600
        let m = (s % 3600) / 60; let sec = s % 60
        if d > 0 { return "\(d)d \(h)h \(m)m \(sec)s" }
        if h > 0 { return "\(h)h \(m)m \(sec)s" }
        return "\(m)m \(sec)s"
    }
}

// MARK: - Sub-Views

private struct AlarmRow: View {
    let alarm: IncidentDetail.PrimaryAlarm

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                StateBadge(label: alarm.state)
                Text(alarm.type)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(alarm.name)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            if !alarm.output.isEmpty {
                Text(alarm.output)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let t = alarm.time {
                Text(formatAlarmDate(t))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func formatAlarmDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f.string(from: date)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(minWidth: 110, alignment: .leading)
            Spacer()
            Text(value)
                .font(.subheadline)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct StateBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color)
            .cornerRadius(5)
    }

    private var color: Color {
        switch label.uppercased() {
        case "OPEN":                     return .red
        case "CRITICAL":                 return .red
        case "MAJOR":                    return .orange
        case "WARNING", "MINOR":         return Color(red: 0.75, green: 0.55, blue: 0)
        case "OK", "RESOLVED", "CLOSED": return .green
        case "ACKNOWLEDGED", "ACK":      return .blue
        default:                         return Color(.systemGray)
        }
    }
}
