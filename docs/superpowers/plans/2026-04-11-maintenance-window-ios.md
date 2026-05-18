# Maintenance Window – iOS Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update `MaintenanceWindowSheet.swift` so the description field matches the shared spec — correct prefix format using the stored ACK username, non-editable prefix displayed above the editable note field, 255-char limit, and amber character counter.

**Architecture:** All changes are confined to `MaintenanceWindowSheet.swift`. The prefix is built once at init from `@AppStorage("netreo_ack_user")` and a wall-clock timestamp. State is split into `prefix` (constant) and `userNote` (editable). The submitted comment is `prefix + userNote`. No changes to the API service, view model, or calling views.

**Tech Stack:** Swift, SwiftUI, AppStorage

---

### Task 1: Update MaintenanceWindowSheet

**Files:**
- Modify: `ios/BeNeM/Views/MaintenanceWindowSheet.swift`

- [ ] **Step 1: Replace the file with the updated implementation**

Replace the full contents of `ios/BeNeM/Views/MaintenanceWindowSheet.swift` with:

```swift
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
```

Key changes vs. the old file:
- `@AppStorage("netreo_ack_user") private var ackUser = ""` added
- `prefix` is a `let` built in `init` from `UserDefaults` + wall-clock timestamp (`"Created by <user> on YYYY-MM-DD HH:MM: "`)
- `comment` state renamed to `userNote` (stores only the user-typed portion)
- `createWindow()` sends `prefix + userNote` as the comment
- `remaining` computed property: `max(0, 255 - prefix.count - userNote.count)`
- Description section: `Text(prefix)` (footnote, secondary) above `TextField("optional note…")`; `.onChange` clamps to `255 - prefix.count` chars; footer shows `"\(remaining) left"` amber when ≤ 20

Note: `init` reads `UserDefaults.standard` directly (not `@AppStorage`) because `@AppStorage` is not available before `self` is initialised.

- [ ] **Step 2: Build**

```bash
cd ios && xcodebuild -scheme BeNeM -destination 'platform=iOS,name=TomiPhone13' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Deploy and smoke-test**

```bash
./build_and_deploy.sh
```

On device:
1. Open the app → Devices tab → tap any device → tap the wrench icon
2. Verify the Description section shows two rows:
   - Row 1: greyed footnote text `"Created by <yourUsername> on <today's date HH:MM>: "`
   - Row 2: empty text field with placeholder `"optional note…"`
3. Verify footer shows e.g. `"217 left"` (or similar, based on prefix length)
4. Type a note — counter decrements
5. Paste a very long string — verify it gets clamped and counter never goes below 0
6. When ≤ 20 chars remain, verify the counter turns amber/yellow
7. Tap Create — verify the success alert appears and the sheet dismisses

- [ ] **Step 4: Commit**

```bash
git add ios/BeNeM/Views/MaintenanceWindowSheet.swift
git commit -m "feat(ios): maintenance window description parity

- Non-editable prefix: 'Created by <ackUser> on YYYY-MM-DD HH:MM: '
- ackUser read from AppStorage (netreo_ack_user)
- Editable note field below prefix (Option A form layout)
- 255-char total limit enforced; amber counter at ≤ 20 remaining

Co-Authored-By: Claude Sonnet 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Mark feature shipped in shared spec

**Files:**
- Modify: `shared/feature-spec.md`

- [ ] **Step 1: Update the status line**

In `shared/feature-spec.md`, find the Maintenance Windows feature block and change:

```
**Status:** shipped-pwa
```

to:

```
**Status:** shipped-both
```

- [ ] **Step 2: Commit**

```bash
git add shared/feature-spec.md
git commit -m "docs(shared): mark maintenance window as shipped-both

Co-Authored-By: Claude Sonnet 4.6 (1M context) <noreply@anthropic.com>"
```
