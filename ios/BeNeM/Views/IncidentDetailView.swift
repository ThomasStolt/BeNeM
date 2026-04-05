import SwiftUI

private let alwaysShownAlarmColors: [AlarmColor] = [.green, .blue, .yellow, .orange, .red]

struct IncidentDetailView: View {
    let incident: NetreoIncident
    let apiService: NetreoAPIService
    let preloadedAlarmCounts: [AlarmColor: Int]?

    @State private var detail: IncidentDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var currentStatus: NetreoIncident.IncidentStatus
    @State private var isAcking = false
    @AppStorage("netreo_ack_user") private var ackUser = ""
    @AppStorage("refresh_interval") private var refreshInterval: Double = 120.0

    init(incident: NetreoIncident, apiService: NetreoAPIService, preloadedAlarmCounts: [AlarmColor: Int]?) {
        self.incident = incident
        self.apiService = apiService
        self.preloadedAlarmCounts = preloadedAlarmCounts
        self._currentStatus = State(initialValue: incident.status)
    }

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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Incident Detail")
                    .font(.headline)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                AutoRefreshButton(
                    interval: refreshInterval,
                    isLoading: isLoading,
                    action: loadDetail
                )
            }
        }
        .task { await loadDetail() }
    }

    // MARK: - Main Content

    @ViewBuilder
    private func detailContent(_ d: IncidentDetail) -> some View {
        List {
            // ── Status Section ──────────────────────────────────────────
            Section {
                HStack(spacing: 0) {
                    // ACK / UnACK button
                    let isAlarmsCleared = d.incidentState.uppercased() == "ALARMS CLEARED"
                    if isAlarmsCleared {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundColor(Color(.systemGray4))
                    } else if isAcking {
                        ProgressView()
                            .frame(width: 36, height: 36)
                    } else if currentStatus == .acknowledged {
                        Button {
                            Task { await toggleAck() }
                        } label: {
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                                .font(.largeTitle)
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            Task { await toggleAck() }
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.largeTitle)
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                    let stateLabel: String = {
                        if currentStatus == .acknowledged { return "ACK" }
                        if d.incidentState.uppercased() == "ACKNOWLEDGED" { return "OPEN" }
                        return d.incidentState
                    }()
                    HStack(spacing: 6) {
                        Text("Status:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        StateBadge(label: stateLabel)
                    }
                    Spacer()

                    if let counts = preloadedAlarmCounts {
                        HStack(spacing: 4) {
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
                InfoRow(label: "Incident ID",    value: incident.incidentID)
                InfoRow(label: "Title",          value: d.title)
                InfoRow(label: "Device",         value: d.deviceName)
                let ip = d.deviceIP?.isEmpty == false ? d.deviceIP : incident.deviceIP
                if let ip, !ip.isEmpty {
                    InfoRow(label: "IP",         value: ip)
                }
                InfoRow(label: "Alert Type",     value: d.alertType ?? "—")
                if let openTime = d.openTime {
                    InfoRow(label: "Created",    value: formatDate(openTime))
                    InfoRow(label: "Duration",   value: durationString(from: openTime))
                }
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

    private func toggleAck() async {
        isAcking = true
        let user = ackUser.isEmpty ? "mobile" : ackUser
        if currentStatus == .acknowledged {
            let ok = try? await apiService.unacknowledgeIncident(incidentID: incident.incidentID, user: user)
            if ok == true {
                currentStatus = .active
                if let fresh = try? await apiService.fetchIncidentDetail(incidentID: incident.incidentID) {
                    detail = fresh
                }
            }
        } else {
            let ok = try? await apiService.acknowledgeIncident(incidentID: incident.incidentID, user: user)
            if ok == true {
                currentStatus = .acknowledged
                if let fresh = try? await apiService.fetchIncidentDetail(incidentID: incident.incidentID) {
                    detail = fresh
                }
            }
        }
        isAcking = false
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
        let s = max(0, Int(Date().timeIntervalSince(start)))
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
                .frame(minWidth: 100, alignment: .leading)
            Spacer()
            Text(value)
                .font(.subheadline)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 2)
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
        case "CRITICAL", "DOWN":         return .red
        case "MAJOR", "UNREACHABLE":     return .orange
        case "WARNING", "MINOR":         return Color(red: 0.75, green: 0.55, blue: 0)
        case "OK", "RESOLVED", "CLOSED", "UP", "NORMAL", "RECOVERY", "CLEARED", "ALARMS CLEARED": return Color(red: 0.13, green: 0.55, blue: 0.13)
        case "ACKNOWLEDGED", "ACK":      return .blue
        default:                         return Color(.systemGray)
        }
    }
}
