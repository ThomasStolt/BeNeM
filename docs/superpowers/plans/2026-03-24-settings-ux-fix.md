# Settings UX Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix three Settings screen bugs: navigation regression when clearing credentials, mid-edit tab jumps, and test connection using the wrong endpoint.

**Architecture:** Three targeted file changes — a one-line navigation guard in ContentView, two field type changes in QuickConfigView, and a deferred-save refactor plus rewritten testConnection() in SettingsView. No new files. No new abstractions.

**Tech Stack:** Swift 5.9+, SwiftUI, AppStorage, URLSession. iOS app — no unit test target exists. Verification is via `xcodebuild` compile check and manual device testing using `./build_and_deploy.sh`.

---

## File Map

| File | What changes |
|---|---|
| `BeNeM/ContentView.swift` | One-line guard in `onChange(of: apiService == nil)` |
| `BeNeM/Views/QuickConfigView.swift` | Two `TextField` → `SecureField` replacements |
| `BeNeM/Views/SettingsView.swift` | Draft state vars, `onAppear` init, `hasUnsavedChanges`, Save toolbar button, rewritten `testConnection()` |

---

## Task 1: ContentView — Navigation Guard

**Files:**
- Modify: `BeNeM/ContentView.swift:44-46`

- [ ] **Step 1: Make the change**

In `ContentView.swift`, find the `onChange(of: apiService == nil)` modifier (around line 44). Change:

```swift
.onChange(of: apiService == nil) { _, isNil in
    if isNil { selectedTab = 0 }
}
```

to:

```swift
.onChange(of: apiService == nil) { _, isNil in
    if isNil && selectedTab != 3 { selectedTab = 0 }
}
```

`selectedTab == 3` is the Settings tab in both the 2-tab (unconfigured) and 4-tab (configured) layouts.

- [ ] **Step 2: Build to verify no compile errors**

```bash
xcodebuild -project BeNeM.xcodeproj -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Manual verification**

Run `./build_and_deploy.sh`. In the app:
1. Go to Settings, clear the Base URL field entirely.
2. Verify you stay on the Settings screen (previously you were kicked to the Welcome screen).

- [ ] **Step 4: Commit**

```bash
git add BeNeM/ContentView.swift
git commit -m "fix: stay on Settings tab when credentials are cleared"
```

---

## Task 2: QuickConfigView — SecureField for API Key and PIN

**Files:**
- Modify: `BeNeM/Views/QuickConfigView.swift:26-31`

- [ ] **Step 1: Change API Key TextField to SecureField**

In `QuickConfigView.swift`, find (around line 26):

```swift
TextField("API Key", text: $apiKey)
    .textFieldStyle(RoundedBorderTextFieldStyle())
    .autocapitalization(.none)
```

Change `TextField` to `SecureField`. `SecureField` does not accept `.autocapitalization`, so remove that modifier:

```swift
SecureField("API Key", text: $apiKey)
    .textFieldStyle(RoundedBorderTextFieldStyle())
```

- [ ] **Step 2: Change PIN TextField to SecureField**

Find (around line 30):

```swift
TextField("PIN (SaaS only - optional)", text: $pin)
    .textFieldStyle(RoundedBorderTextFieldStyle())
    .autocapitalization(.none)
```

Change to:

```swift
SecureField("PIN (SaaS only - optional)", text: $pin)
    .textFieldStyle(RoundedBorderTextFieldStyle())
```

- [ ] **Step 3: Build to verify no compile errors**

```bash
xcodebuild -project BeNeM.xcodeproj -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Manual verification**

Run `./build_and_deploy.sh`. Open the app without configured credentials so you see the Welcome screen. Tap the API Key and PIN fields — characters should be masked (dots), not visible.

- [ ] **Step 5: Commit**

```bash
git add BeNeM/Views/QuickConfigView.swift
git commit -m "fix: mask API key and PIN on Welcome screen"
```

---

## Task 3: SettingsView — Draft State + Save Button

**Files:**
- Modify: `BeNeM/Views/SettingsView.swift`

This task adds the four draft `@State` vars, `onAppear` initialisation, the `hasUnsavedChanges` computed property, and the Save toolbar button. The existing form fields are re-bound to draft vars. `testConnection()` is left unchanged in this task (updated in Task 4).

- [ ] **Step 1: Add draft state vars**

At the top of `SettingsView`, after the existing `@AppStorage` declarations and before the `@State private var isTesting` line, add:

```swift
// Draft state — held locally until Save is tapped
@State private var draftBaseURL = ""
@State private var draftApiKey = ""
@State private var draftPin = ""
@State private var draftAckUser = ""
```

- [ ] **Step 2: Add hasUnsavedChanges computed property**

After the existing `@State` declarations block, add:

```swift
private var hasUnsavedChanges: Bool {
    draftBaseURL != baseURL ||
    draftApiKey != apiKey ||
    draftPin != pin ||
    draftAckUser != ackUser
}
```

- [ ] **Step 3: Bind form fields to draft vars**

In the `body`, find the "BHNM Server" section. Replace the four field bindings:

```swift
// Before
TextField("Base URL", text: $baseURL)
    .autocapitalization(.none)
    .keyboardType(.URL)

SecureField("API Key", text: $apiKey)

SecureField("PIN (SaaS only)", text: $pin)

TextField("ACK User", text: $ackUser)
    .autocapitalization(.none)
```

```swift
// After
TextField("Base URL", text: $draftBaseURL)
    .autocapitalization(.none)
    .keyboardType(.URL)

SecureField("API Key", text: $draftApiKey)

SecureField("PIN (SaaS only)", text: $draftPin)

TextField("ACK User", text: $draftAckUser)
    .autocapitalization(.none)
```

- [ ] **Step 4: Add onAppear to initialise drafts from AppStorage**

Add `.onAppear` to the **`NavigationView`** (the outermost view in `body`), after the existing `.alert(...)` modifier. Attaching to `NavigationView` (not `Form`) ensures the handler re-fires when returning from pushed views like `AutoDiscoveryView`, which may have written a new URL to AppStorage.

```swift
.onAppear {
    draftBaseURL = baseURL
    draftApiKey = apiKey
    draftPin = pin
    draftAckUser = ackUser
}
```

- [ ] **Step 5: Add Save toolbar button**

On the same view, add a `.toolbar` modifier:

```swift
.toolbar {
    if hasUnsavedChanges {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button("Save") {
                baseURL = draftBaseURL
                apiKey = draftApiKey
                pin = draftPin
                ackUser = draftAckUser
            }
            .fontWeight(.semibold)
        }
    }
}
```

- [ ] **Step 6: Build to verify no compile errors**

```bash
xcodebuild -project BeNeM.xcodeproj -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Manual verification**

Run `./build_and_deploy.sh`. In the app:

1. Go to Settings. Edit the Base URL field. Verify a "Save" button appears in the top-right.
2. Tap elsewhere (don't tap Save). Switch tabs and come back to Settings. Verify the unsaved edit is gone (reverted to saved value).
3. Edit the Base URL, tap "Save". Verify the Save button disappears.
4. Clear the Base URL and tap Save. Verify you stay on the Settings screen.
5. Enter a URL while API key is already set and tap Save. Verify the app connects (Dashboard becomes accessible) without navigating away from Settings mid-edit.

- [ ] **Step 8: Commit**

```bash
git add BeNeM/Views/SettingsView.swift
git commit -m "feat: deferred save with explicit Save button in Settings"
```

---

## Task 4: SettingsView — Rewrite testConnection()

**Files:**
- Modify: `BeNeM/Views/SettingsView.swift:147-245` (the `testConnection()` function)

- [ ] **Step 1: Replace testConnection() entirely**

Find the entire `testConnection()` function (from `@MainActor` to its closing `}`). Replace it with:

```swift
@MainActor
private func testConnection() async {
    isTesting = true
    defer { isTesting = false }

    let trimmedURL = draftBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmedURL), url.scheme != nil, url.host != nil else {
        alertTitle = "Invalid URL"
        alertMessage = "The URL \"\(trimmedURL)\" is not a valid format.\n\nExample: https://netreo.example.com"
        showingAlert = true
        return
    }

    // Always test against the actual endpoint the app uses at runtime
    guard let testURL = URL(string: "\(trimmedURL.trimmingSuffix("/"))/fw/index.php?r=restful/devices/list") else {
        alertTitle = "Invalid URL"
        alertMessage = "Could not construct test URL from \"\(trimmedURL)\"."
        showingAlert = true
        return
    }

    var request = URLRequest(url: testURL, timeoutInterval: 15)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

    var bodyItems = [URLQueryItem(name: "password", value: draftApiKey)]
    if !draftPin.isEmpty {
        bodyItems.append(URLQueryItem(name: "pin", value: draftPin))
    }
    var comps = URLComponents()
    comps.queryItems = bodyItems
    request.httpBody = comps.percentEncodedQuery?.data(using: .utf8)

    do {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: sessionConfig)

        let (data, response) = try await session.data(for: request)
        let http = response as! HTTPURLResponse
        let statusCode = http.statusCode

        switch statusCode {
        case 200:
            // Parse device count using the same two-shape JSON the app handles at runtime
            var deviceCount = 0
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let arr = json["devices"] as? [[String: Any]] {
                    deviceCount = arr.count
                } else if let nested = json["data"] as? [String: Any],
                          let arr = nested["devices"] as? [[String: Any]] {
                    deviceCount = arr.count
                }
            }
            if deviceCount > 0 {
                alertTitle = "Connection successful"
                alertMessage = "Found \(deviceCount) device\(deviceCount == 1 ? "" : "s")."
            } else {
                alertTitle = "Connected — no devices found"
                alertMessage = "The server responded successfully but returned no devices.\n\nCheck that your API key has permission to list devices."
            }
        case 401, 403:
            alertTitle = "Authentication failed"
            alertMessage = "HTTP \(statusCode): The server rejected the credentials.\n\nCheck your API key and PIN."
        case 404:
            alertTitle = "Endpoint not found"
            alertMessage = "HTTP 404: The API endpoint was not found.\n\nCheck the base URL."
        case 500...599:
            alertTitle = "Server error"
            alertMessage = "HTTP \(statusCode): The server reported an internal error."
        default:
            let bodyPreview = String(data: data.prefix(300), encoding: .utf8) ?? "(unreadable)"
            alertTitle = "Unexpected response"
            alertMessage = "HTTP \(statusCode)\n\nResponse: \(bodyPreview)"
        }
    } catch let urlError as URLError {
        alertTitle = "Connection failed"
        switch urlError.code {
        case .notConnectedToInternet:
            alertMessage = "No internet connection."
        case .cannotFindHost:
            alertMessage = "Host not found: \"\(url.host ?? trimmedURL)\" could not be resolved.\n\nCheck the URL and that your VPN is connected if this is an internal server."
        case .cannotConnectToHost:
            alertMessage = "Cannot connect to \"\(url.host ?? trimmedURL)\".\n\nCheck the URL, port, and firewall settings."
        case .timedOut:
            alertMessage = "Timed out after 15 seconds.\n\nURL: \(testURL.absoluteString)"
        case .secureConnectionFailed, .serverCertificateUntrusted:
            alertMessage = "SSL/TLS error: \(urlError.localizedDescription)"
        default:
            alertMessage = "\(urlError.localizedDescription) (code \(urlError.code.rawValue))"
        }
    } catch {
        alertTitle = "Error"
        alertMessage = error.localizedDescription
    }

    showingAlert = true
}
```

- [ ] **Step 2: Update the Test Connection button's disabled predicate**

Find the Test Connection section button (around line 86):

```swift
.disabled(baseURL.isEmpty || apiKey.isEmpty || isTesting)
```

Change to:

```swift
.disabled(draftBaseURL.isEmpty || draftApiKey.isEmpty || isTesting)
```

- [ ] **Step 3: Build to verify no compile errors**

```bash
xcodebuild -project BeNeM.xcodeproj -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Manual verification**

Run `./build_and_deploy.sh`. In the app, go to Settings → Connection Test:

1. **Valid credentials:** Enter correct URL and API key (don't save), tap Test. Verify the result shows device count (not just "server responded with HTTP 200").
2. **Wrong API key:** Enter a bad API key, tap Test. Verify you get "Authentication failed" (not a generic success).
3. **Wrong URL:** Enter a URL for a non-existent host, tap Test. Verify you get "Host not found".
4. **Test before saving:** Enter new credentials, tap Test without tapping Save. Verify the test uses the typed values, not the last-saved values.

- [ ] **Step 5: Commit**

```bash
git add BeNeM/Views/SettingsView.swift
git commit -m "fix: test connection against actual API endpoint using draft credentials"
```

---

## Done

All three bugs fixed:
- Clearing credentials in Settings no longer navigates away (Task 1 + Task 3)
- Typing in Settings no longer causes mid-edit tab jumps (Task 3)
- Test Connection validates API key against the real endpoint (Task 4)
- API key and PIN are masked on the Welcome screen (Task 2)
