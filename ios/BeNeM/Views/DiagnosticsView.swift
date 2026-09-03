import SwiftUI

/// Connection diagnostics sheet (opened by tapping the connection badge).
/// Does NOT fetch for itself — it reads the global ConnectionMonitor's cached
/// poll result (the same truth as the badge); pull-to-refresh polls now.
struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var callLog = ClientCallLog.shared
    @ObservedObject private var connection = ConnectionMonitor.shared

    private var result: DiagnosticsResult? { connection.lastResult }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    pipeline
                    feedsSection
                    errorsSection
                    callLogSection
                    healthSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .refreshable { await ConnectionMonitor.shared.pollNow() }
            .overlay {
                if result == nil { ProgressView() }
            }
        }
    }

    // MARK: Pipeline

    private var bhnm: Diagnostics.Bhnm? { result?.diagnostics?.server.bhnm }
    private var reachedMiddleware: Bool { result?.reachedMiddleware ?? false }

    private var pipeline: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Connection path")
            HStack(alignment: .top, spacing: 0) {
                hopNode("iphone", "App", up: true, detail: "running")
                hopLink(up: reachedMiddleware,
                        label: result?.appToMiddlewareMs.map { "\($0) ms" } ?? "—")
                hopNode("server.rack", "Middleware", up: reachedMiddleware,
                        detail: reachedMiddleware ? "up" : "unreachable")
                hopLink(up: bhnm?.reachable == true, label: bhnmLatencyLabel)
                hopNode("externaldrive.fill", "BHNM",
                        up: bhnm?.reachable == true,
                        detail: bhnm?.reachable == nil ? "checking"
                              : (bhnm?.reachable == true ? "reachable" : "down"))
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
        }
    }

    private var bhnmLatencyLabel: String {
        guard let b = bhnm, b.reachable != nil else { return "—" }
        guard b.reachable == true, let ms = b.latency_ms else { return "down" }
        // Age = the middleware monitor's last probe (≤ probe interval when
        // healthy) — shown so the number isn't misread as a live measurement.
        if let age = b.last_success_age_seconds { return "\(ms) ms · \(agoText(age))" }
        return "\(ms) ms"
    }

    private func hopNode(_ symbol: String, _ name: String, up: Bool, detail: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color(.tertiarySystemGroupedBackground)))
                .overlay(Circle().stroke(up ? Color.green : Color.red, lineWidth: 2))
                .foregroundColor(up ? .primary : .red)
            Text(name).font(.caption2).fontWeight(.semibold)
            Text(detail).font(.system(size: 9)).foregroundColor(up ? .green : .red)
        }
        .frame(width: 74)
    }

    private func hopLink(up: Bool, label: String) -> some View {
        VStack(spacing: 3) {
            ZStack {
                if up {
                    Capsule().fill(Color.green).frame(height: 3)
                } else {
                    HStack(spacing: 6) {
                        Capsule().fill(Color.red).frame(height: 3)
                        Image(systemName: "bolt.slash.fill").font(.system(size: 11)).foregroundColor(.red)
                        Capsule().fill(Color.red).frame(height: 3)
                    }
                }
            }
            .frame(height: 44)
            Text(label).font(.system(size: 9, design: .monospaced))
                .foregroundColor(up ? .green : .red)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Feeds

    private var feedsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Feeds")
            card {
                ForEach(["tactical", "incidents", "thresholds", "maintenance_map"], id: \.self) { key in
                    if let f = result?.diagnostics?.server.feeds[key] {
                        feedRow(key == "maintenance_map" ? "Maint. map" : key.capitalized, f,
                                unit: key == "maintenance_map" ? "hosts" : nil)
                        if key != "maintenance_map" { Divider() }
                    }
                }
                if result?.diagnostics == nil {
                    Text("No data").font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }

    private func feedRow(_ name: String, _ f: Diagnostics.Feed, unit: String? = nil) -> some View {
        // spec rev 5 §11.3: the maintenance-map feed counts host rows — label the unit
        let countText = f.count.map { c in unit.map { u in "\(c) \(u)" } ?? String(c) } ?? "—"
        return HStack {
            Text(name).font(.subheadline).fontWeight(.medium).frame(width: 90, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(countText)\(f.age_seconds.map { " · \(agoText($0))" } ?? "")")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Text((f.cached ?? false) ? "CACHED" : "LIVE")
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background((f.cached ?? false) ? Color.blue.opacity(0.18) : Color.green)
                .foregroundColor((f.cached ?? false) ? .blue : .white)
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
    }

    // MARK: Errors

    private var errorsSection: some View {
        Group {
            if let b = bhnm {
                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel("Errors · this server")
                    card {
                        if b.reachable != false && (b.consecutive_failures ?? 0) == 0 {
                            Label("No recent errors", systemImage: "checkmark.circle.fill")
                                .font(.subheadline).foregroundColor(.green)
                        } else {
                            Label(b.reachable == true ? "Recovering" : "BHNM unreachable",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline).foregroundColor(.red)
                            row("Consecutive failures", "\(b.consecutive_failures ?? 0)")
                            if let e = b.last_error {
                                row("Last error\(b.last_error_age_seconds.map { " · \(agoText($0))" } ?? "")", e)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Recent calls

    private var callLogSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Recent calls")
            card {
                if callLog.entries.isEmpty {
                    Text("No calls yet").font(.caption).foregroundColor(.secondary)
                } else {
                    ForEach(callLog.entries.prefix(12)) { e in
                        HStack {
                            Text(e.endpoint).font(.system(size: 11, design: .monospaced))
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(e.status == -1 ? "ERR" : "\(e.status)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(e.status == -1 || e.status >= 400 ? .red : .green)
                            Text("\(e.ms)ms").font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary).frame(width: 56, alignment: .trailing)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    // MARK: Health

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Middleware · /health")
            card {
                let m = result?.diagnostics?.middleware
                row("Middleware version", m?.version ?? "—")
                Divider()
                row("Registered devices", m?.registered_devices.map(String.init) ?? "—")
                Divider()
                row("Server", result?.diagnostics?.server.host ?? "—")
                Divider()
                row("BHNM source", bhnm?.source ?? "—")
            }
        }
    }

    // MARK: Helpers

    private func sectionLabel(_ t: String) -> some View {
        Text(t.uppercased()).font(.caption2).fontWeight(.semibold)
            .foregroundColor(.secondary).kerning(0.6)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) { content() }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.caption).foregroundColor(.secondary)
            Spacer()
            Text(v).font(.caption).fontWeight(.medium).lineLimit(2).multilineTextAlignment(.trailing)
        }
    }

    private func agoText(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }
}
