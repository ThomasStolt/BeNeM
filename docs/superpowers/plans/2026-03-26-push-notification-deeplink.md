# Push Notification Deep Link Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tapping a push notification opens BeNeM directly to the IncidentDetailView for the notified incident.

**Architecture:** The middleware embeds `incident_id` in the APNs payload. AppDelegate handles the notification tap (both foreground and cold-launch) and stores the incident ID on itself. ContentView reads it on appear and via `NotificationCenter`, switches to the Incidents tab, and passes the ID to IncidentListView, which loads incidents if needed and navigates to the matching one.

**Tech Stack:** Swift/SwiftUI, UserNotifications framework, Python/FastAPI (middleware)

---

### Task 1: Embed incident_id in APNs payload (middleware)

**Files:**
- Modify: `bhnm-apns/apns.py`
- Modify: `bhnm-apns/main.py`

- [ ] **Step 1: Update `send_notification` to accept and embed `incident_id`**

In `apns.py`, update the function:

```python
def send_notification(device_token: str, title: str, body: str, incident_id: str = "") -> tuple[bool, int]:
    """Returns (success, http_status_code)."""
    url = f"https://{APNS_HOST}/3/device/{device_token}"
    headers = {
        "authorization": f"bearer {_get_jwt()}",
        "apns-topic": APNS_BUNDLE_ID,
        "apns-push-type": "alert",
        "apns-priority": "10",
    }
    payload = {
        "aps": {
            "alert": {"title": title, "body": body},
            "sound": "default"
        }
    }
    if incident_id:
        payload["incident_id"] = incident_id
    try:
        with httpx.Client(http2=True) as client:
            r = client.post(url, json=payload, headers=headers, timeout=10)
        success = r.status_code == 200
        if not success:
            print(f"[APNs] Failed ({r.status_code}): {r.text}")
        return success, r.status_code
    except Exception as e:
        print(f"[APNs] Error: {e}")
        return False, 0
```

- [ ] **Step 2: Update `send_to_all` to pass `incident_id` through**

```python
def send_to_all(tokens: list[str], title: str, body: str, incident_id: str = "") -> list[str]:
    stale_tokens = []
    for token in tokens:
        success, status = send_notification(token, title, body, incident_id)
        if status == 410:
            stale_tokens.append(token)
        elif success:
            print(f"[APNs] ✓ Sent to ...{token[-8:]}")
    return stale_tokens
```

- [ ] **Step 3: Pass `incident_id` from webhook handler in `main.py`**

In `main.py`, update the `send_to_all` call (already extracts `incident_id` from payload):

```python
stale = send_to_all(tokens, title, body, incident_id)
```

- [ ] **Step 4: Deploy to Ubuntu server**

```bash
cd ~/bhnm-apns
git pull
sudo systemctl restart bhnm-apns
sudo systemctl status bhnm-apns
```

- [ ] **Step 5: Test — verify APNs accepts the extended payload**

```bash
curl -X POST http://localhost:8889/webhook \
  -H "Content-Type: application/json" \
  -d '{"incident_id":"test-999","hostname":"raspi-050","host_state":"DOWN","notification_type":"PROBLEM","site":"Home","service_desc":"Host Check","output":"PING CRITICAL"}'
```

Expected server log: `[APNs] ✓ Sent to ...`

- [ ] **Step 6: Commit middleware changes**

```bash
cd ~/bhnm-apns
git add apns.py main.py
git commit -m "feat: embed incident_id in APNs payload for deep linking"
git push
```

---

### Task 2: Handle notification tap in AppDelegate

**Files:**
- Modify: `BeNeM/BeNeM/AppDelegate.swift`

The cold-launch case (app killed when notification arrives) requires reading `launchOptions` in `didFinishLaunchingWithOptions` because `NotificationCenter` subscribers in SwiftUI views aren't yet mounted at that point. We store `pendingIncidentID` on `AppDelegate` itself so `ContentView` can read it on `.onAppear`.

- [ ] **Step 1: Replace `AppDelegate.swift` entirely**

```swift
import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    /// Accessed by ContentView for cold-launch deep linking.
    static weak var shared: AppDelegate?

    /// Set when a notification tap arrives before SwiftUI is fully mounted (cold launch).
    var pendingIncidentID: String? = nil

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        AppDelegate.shared = self

        // Cold-launch: app was killed and user tapped notification
        if let notification = launchOptions?[.remoteNotification] as? [String: Any],
           let incidentID = notification["incident_id"] as? String {
            pendingIncidentID = incidentID
        }

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("[APNs] Device token: \(token)")
        registerWithMiddleware(token: token)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[APNs] Registration failed: \(error)")
    }

    // Show notification banner even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // Handle notification tap (app in background or foreground)
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let incidentID = userInfo["incident_id"] as? String, !incidentID.isEmpty {
            NotificationCenter.default.post(
                name: .pushNotificationIncidentTapped,
                object: nil,
                userInfo: ["incident_id": incidentID]
            )
        }
        completionHandler()
    }

    private func registerWithMiddleware(token: String) {
        let middlewareURL = UserDefaults.standard.string(forKey: "push_middleware_url") ?? ""
        guard !middlewareURL.isEmpty, let url = URL(string: "\(middlewareURL)/register") else {
            print("[APNs] No middleware URL configured — skipping token registration.")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "token": token,
            "device_name": UIDevice.current.name
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                print("[APNs] Middleware registration error: \(error)")
            } else if let http = response as? HTTPURLResponse {
                print("[APNs] Middleware responded: \(http.statusCode)")
            }
        }.resume()
    }
}

extension Notification.Name {
    static let pushNotificationIncidentTapped = Notification.Name("PushNotificationIncidentTapped")
}
```

- [ ] **Step 2: Build to verify no errors**

```bash
xcodebuild -project BeNeM.xcodeproj -scheme BeNeM -destination 'id=00008110-00167D41263A801E' build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `** BUILD SUCCEEDED **`

---

### Task 3: ContentView listens and switches to Incidents tab

**Files:**
- Modify: `BeNeM/BeNeM/ContentView.swift`

- [ ] **Step 1: Add `pendingIncidentID` state, notification listener, and cold-launch handling**

Add property to `ContentView`:

```swift
@State private var pendingIncidentID: String? = nil
```

Add `.onReceive` for background-tap deep links (alongside existing `.onAppear`):

```swift
.onReceive(NotificationCenter.default.publisher(for: .pushNotificationIncidentTapped)) { notification in
    guard let id = notification.userInfo?["incident_id"] as? String else { return }
    // If already on Incidents tab, reset nav stack first so we push to root
    if selectedTab == 1 { incidentNavResetID = UUID() }
    selectedTab = 1
    pendingIncidentID = id
}
```

Add cold-launch handling inside the existing `.onAppear`:

```swift
.onAppear {
    updateAPIService()
    if apiService == nil { selectedTab = 3 }
    // Cold-launch: AppDelegate captured the incident ID before SwiftUI mounted
    if let id = appDelegate.pendingIncidentID {
        appDelegate.pendingIncidentID = nil
        selectedTab = 1
        pendingIncidentID = id
    }
}
```

In `ContentView.onAppear`, use the singleton set in Task 2:
```swift
if let id = AppDelegate.shared?.pendingIncidentID {
    AppDelegate.shared?.pendingIncidentID = nil
    selectedTab = 1
    pendingIncidentID = id
}
```

- [ ] **Step 2: Pass `pendingIncidentID` binding to `IncidentListView`**

```swift
IncidentListView(apiService: service, navResetID: incidentNavResetID, pendingIncidentID: $pendingIncidentID)
```

- [ ] **Step 3: Build (will fail until Task 4 — that is expected)**

```bash
xcodebuild -project BeNeM.xcodeproj -scheme BeNeM -destination 'id=00008110-00167D41263A801E' build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

---

### Task 4: IncidentListView navigates to the pending incident

**Files:**
- Modify: `BeNeM/BeNeM/Views/IncidentListView.swift`

- [ ] **Step 1: Add `pendingIncidentID` binding to `IncidentListView`**

Add the binding property and update `init`:

```swift
@Binding private var pendingIncidentID: String?

init(apiService: NetreoAPIService, navResetID: UUID, pendingIncidentID: Binding<String?>) {
    self._viewModel = StateObject(wrappedValue: IncidentListViewModel(apiService: apiService))
    self.apiService = apiService
    self.navResetID = navResetID
    self._pendingIncidentID = pendingIncidentID
}
```

- [ ] **Step 2: Add `navigateToPendingIncident()` helper**

```swift
private func navigateToPendingIncident() {
    guard let id = pendingIncidentID else { return }
    if let incident = viewModel.incidents.first(where: { $0.incidentID == id }) {
        pendingIncidentID = nil
        navPath.append(incident)
    } else {
        // Incident not found (resolved/closed) — clear pending ID silently
        pendingIncidentID = nil
    }
}
```

- [ ] **Step 2b: Update `#Preview` at the bottom of `IncidentListView.swift` to match new `init`**

Find the `#Preview` macro and update the `IncidentListView` call to include the new parameter:

```swift
IncidentListView(apiService: ..., navResetID: UUID(), pendingIncidentID: .constant(nil))
```

- [ ] **Step 3: Replace the existing `.onChange(of: viewModel.isLoading)` block and add `pendingIncidentID` trigger**

Replace the existing `.onChange(of: viewModel.isLoading)` (do NOT add a second one):

```swift
.onChange(of: viewModel.isLoading) { _, loading in
    guard !loading else { return }
    connectionStatus = viewModel.errorMessage == nil ? .connected : .disconnected
    navigateToPendingIncident()
}
```

Add one `.onChange(of: pendingIncidentID)` — handles the case where incidents are already loaded when the ID arrives:

```swift
.onChange(of: pendingIncidentID) { _, id in
    guard id != nil else { return }
    if viewModel.incidents.isEmpty {
        // Incidents not loaded yet — trigger load; navigation fires in isLoading onChange above
        Task { await viewModel.loadIncidents() }
    } else if !viewModel.isLoading {
        navigateToPendingIncident()
    }
}
```

- [ ] **Step 4: Build and deploy**

```bash
xcodebuild -project BeNeM.xcodeproj -scheme BeNeM -destination 'id=00008110-00167D41263A801E' build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

```bash
xcrun devicectl device install app --device 00008110-00167D41263A801E \
  /Users/thomasstolt/Library/Developer/Xcode/DerivedData/BeNeM-gwfbvcgxlpmlvheswovjholwhghu/Build/Products/Debug-iphoneos/BeNeM.app
```

- [ ] **Step 5: End-to-end test — background tap**

1. Put app in background (Home swipe)
2. Send test webhook with a real incident ID from BHNM
3. Tap notification
4. Expected: Incidents tab opens → IncidentDetailView for that incident

- [ ] **Step 6: End-to-end test — cold launch**

1. Kill app completely (App Switcher → swipe away)
2. Send test webhook
3. Tap notification
4. Expected: app launches → Incidents tab → IncidentDetailView

- [ ] **Step 7: Commit iOS changes**

```bash
git add BeNeM/AppDelegate.swift BeNeM/ContentView.swift BeNeM/Views/IncidentListView.swift
git commit -m "feat: deep link push notifications to incident detail"
```
