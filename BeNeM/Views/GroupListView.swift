import SwiftUI

// Fixed widths shared between header and data rows for alignment
private let kTotalWidth: CGFloat = 38    // "# of Hosts" count column (leftmost)
private let kBadgesWidth: CGFloat = 128  // label + 5 status badges (rightmost)
private let kGap: CGFloat = 8            // gap between count and name

// MARK: - GroupListView

struct GroupListView: View {
    let title: String
    @StateObject private var viewModel: TacticalViewModel
    @AppStorage("refresh_interval") private var refreshInterval: Double = 120.0

    init(title: String, apiService: NetreoAPIService, type: TacticalViewModel.GroupType) {
        self.title = title
        _viewModel = StateObject(wrappedValue: TacticalViewModel(apiService: apiService, type: type))
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.groups.isEmpty {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") { Task { await viewModel.load() } }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.groups.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No entries found")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.showAlarmsOnly && viewModel.filteredGroups.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.largeTitle)
                        .foregroundColor(.green)
                    Text("All groups are healthy")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    columnHeader
                    ForEach(Array(viewModel.filteredGroups.enumerated()), id: \.element.id) { index, group in
                        GroupRow(group: group)
                            .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                            .listRowBackground(index.isMultiple(of: 2)
                                ? Color.clear
                                : Color(.systemGray6).opacity(0.6))
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Image("BMCHelixLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                }
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    viewModel.showAlarmsOnly.toggle()
                } label: {
                    Image(systemName: viewModel.showAlarmsOnly
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                    .foregroundColor(viewModel.showAlarmsOnly ? .accentColor : .primary)
                }
                .padding(.trailing, 6)

                AutoRefreshButton(
                    interval: refreshInterval,
                    isLoading: viewModel.isLoading,
                    action: viewModel.load
                )
            }
        }
        .task {
            if viewModel.groups.isEmpty && viewModel.errorMessage == nil {
                await viewModel.load()
            }
        }
        .refreshable { await viewModel.load() }
    }

    // MARK: Column header

    private var columnHeader: some View {
        HStack(spacing: 0) {
            // "DEVICES" — leftmost, over the count column
            Text("DEVICES")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .fixedSize()
                .frame(width: kTotalWidth, alignment: .center)

            Spacer(minLength: kGap)

            // Group name label — fills remaining space, centred in its column
            Text(title.uppercased())
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)

            // "ALARMS" centered over the 5 badges
            Text("ALARMS")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .frame(width: kBadgesWidth, alignment: .center)
        }
        .padding(.vertical, 4)
        .listRowBackground(Color(.systemGroupedBackground))
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }
}

// MARK: - GroupRow

private struct GroupRow: View {
    let group: GroupSummary

    private let green  = AlarmColor.green.color
    private let yellow = AlarmColor.yellow.color
    private let orange = AlarmColor.orange.color
    private let red    = AlarmColor.red.color
    private let blue   = AlarmColor.blue.color

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Device count — far left, aligned with "Devices" header
            Text("\(group.totalHosts)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .frame(minWidth: kTotalWidth)
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.blue, lineWidth: 1.5))

            Spacer(minLength: kGap)

            // Name
            Text(group.name)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)

            // Metric rows (Hosts / Services / Thresholds / Anomalies) — right side
            VStack(alignment: .trailing, spacing: 2) {
                metricRow(label: "H",
                          green: group.hostsGreen, blue: group.hostsBlue,
                          yellow: group.hostsYellow, orange: group.hostsOrange,
                          red: group.hostsRed)
                metricRow(label: "S",
                          green: group.servicesGreen, blue: group.servicesBlue,
                          yellow: group.servicesYellow, orange: group.servicesOrange,
                          red: group.servicesRed)
                metricRow(label: "T",
                          green: group.thresholdsGreen, blue: group.thresholdsBlue,
                          yellow: group.thresholdsYellow, orange: group.thresholdsOrange,
                          red: group.thresholdsRed)
                metricRow(label: "A",
                          green: group.anomaliesGreen, blue: group.anomaliesBlue,
                          yellow: group.anomaliesYellow, orange: group.anomaliesOrange,
                          red: group.anomaliesRed)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Metric row

    private func metricRow(label: String,
                           green: Int, blue: Int, yellow: Int,
                           orange: Int, red: Int) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 12, alignment: .leading)

            statBadge(count: green,  color: self.green)
            statBadge(count: blue,   color: self.blue)
            statBadge(count: yellow, color: self.yellow, darkText: true)
            statBadge(count: orange, color: self.orange)
            statBadge(count: red,    color: self.red)
        }
        .frame(width: kBadgesWidth, alignment: .center)
    }

    private func statBadge(count: Int, color: Color, darkText: Bool = false) -> some View {
        Group {
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(darkText ? .black : .white)
                    .frame(minWidth: 18)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 2)
                    .background(color)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Text("0")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(Color(.systemGray3))
                    .frame(minWidth: 18)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 2)
            }
        }
    }
}
