import SwiftUI

struct MaintenanceWindowSheet: View {
    let deviceName: String
    let apiService: NetreoAPIService
    let onDismiss: () -> Void

    @AppStorage("netreo_ack_user") private var ackUser = ""

    @State private var selectedDuration: DurationOption = .oneHour
    @State private var customMinutes: String = "60"
    @State private var userNote: String = ""
    @State private var isCreating = false
    @State private var showResult: ResultType?

    private let prefix: String

    enum DurationOption: String, CaseIterable {
        case oneHour = "1h"
        case sixHours = "6h"
        case twelveHours = "12h"
        case twentyFourHours = "24h"
        case sevenDays = "7d"
        case custom = "Custom"

        var minutes: Int? {
            switch self {
            case .oneHour: return 60
            case .sixHours: return 360
            case .twelveHours: return 720
            case .twentyFourHours: return 1440
            case .sevenDays: return 10080
            case .custom: return nil
            }
        }
    }

    enum ResultType {
        case success
        case failure(String)
    }

    init(deviceName: String, apiService: NetreoAPIService, onDismiss: @escaping () -> Void) {
        self.deviceName = deviceName
        self.apiService = apiService
        self.onDismiss = onDismiss

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let stamp = formatter.string(from: Date())
        let user = UserDefaults.standard.string(forKey: "netreo_ack_user") ?? ""
        self.prefix = "Created by \(user.isEmpty ? "unknown" : user) on \(stamp): "
    }

    private var durationMinutes: Int {
        if let fixed = selectedDuration.minutes { return fixed }
        return Int(customMinutes) ?? 60
    }

    private var remaining: Int {
        max(0, 255 - prefix.count - userNote.count)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(deviceName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Section("Duration") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                        ForEach(DurationOption.allCases, id: \.self) { option in
                            Button {
                                selectedDuration = option
                            } label: {
                                Text(option.rawValue)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(selectedDuration == option ? Color.accentColor : Color(.systemGray5))
                                    .foregroundColor(selectedDuration == option ? .white : .primary)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if selectedDuration == .custom {
                        HStack {
                            Text("Minutes")
                            TextField("60", text: $customMinutes)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                Section {
                    Text(prefix)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    TextField("optional note…", text: $userNote)
                        .onChange(of: userNote) { _, new in
                            let limit = 255 - prefix.count
                            if new.count > limit {
                                userNote = String(new.prefix(limit))
                            }
                        }
                } header: {
                    Text("Description")
                } footer: {
                    Text("\(remaining) left")
                        .foregroundColor(remaining <= 20 ? .yellow : .secondary)
                }
            }
            .navigationTitle("Create Maintenance Window")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await createWindow() }
                    }
                    .disabled(isCreating || durationMinutes < 1)
                }
            }
            .alert("Maintenance Window Created",
                   isPresented: Binding(get: { showResult != nil && isSuccess }, set: { if !$0 { onDismiss() } })) {
                Button("OK") { onDismiss() }
            } message: {
                Text("Maintenance window for \(deviceName) will start in 15 minutes.")
            }
            .alert("Error",
                   isPresented: Binding(get: { showResult != nil && !isSuccess }, set: { if !$0 { showResult = nil } })) {
                Button("OK") { showResult = nil }
            } message: {
                if case .failure(let msg) = showResult {
                    Text(msg)
                }
            }
        }
    }

    private var isSuccess: Bool {
        if case .success = showResult { return true }
        return false
    }

    private func createWindow() async {
        isCreating = true
        defer { isCreating = false }
        do {
            let comment = prefix + userNote
            let success = try await apiService.createMaintenanceWindow(
                deviceName: deviceName,
                durationMinutes: durationMinutes,
                comment: comment
            )
            showResult = success ? .success : .failure("BHNM did not confirm the maintenance window.")
        } catch {
            showResult = .failure("Could not create maintenance window.")
        }
    }
}
