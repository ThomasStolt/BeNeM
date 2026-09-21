import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    /// Accessed by ContentView for cold-launch deep linking.
    static weak var shared: AppDelegate?

    /// Set when a notification tap arrives before SwiftUI is fully mounted (cold launch).
    var pendingIncidentID: String? = nil

    /// Caches the APNs device token for re-registration when switching servers.
    var cachedDeviceToken: String? = nil

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Before anything reads UserDefaults: a phone left on API Version "v1"
        // has a broken incidents path and no UI left to fix it (2.13.3).
        LegacySettingsMigration.runIfNeeded()

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
        #if DEBUG
        print("[APNs] Device token: \(token)")
        #endif
        cachedDeviceToken = token
        let ud = UserDefaults.standard
        guard let activeID = ud.string(forKey: "netreo_active_connection_id"), !activeID.isEmpty,
              let conn = ud.loadSavedConnections().first(where: { $0.id.uuidString == activeID }),
              conn.notificationsEnabled else {
            print("[APNs] notificationsEnabled is false for active connection — skipping registration.")
            return
        }
        registerWithMiddleware(token: token, secret: conn.webhookSecret, middlewareURL: conn.middlewareURL)
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
            print("[DeepLink] didReceive — incident_id: \(incidentID)")
            // Always store as pending — covers cold launch where SwiftUI isn't ready yet.
            // ContentView.onAppear picks this up. For warm launch, the NotificationCenter
            // post also fires and is handled by .onReceive.
            pendingIncidentID = incidentID
            NotificationCenter.default.post(
                name: .pushNotificationIncidentTapped,
                object: nil,
                userInfo: ["incident_id": incidentID]
            )
        }
        completionHandler()
    }

    func unregisterWithMiddleware(token: String, secret: String, middlewareURL: String) {
        guard !middlewareURL.isEmpty, let url = URL(string: "\(middlewareURL)/register") else {
            print("[APNs] No middleware URL — skipping token unregistration.")
            return
        }
        guard !secret.isEmpty else {
            print("[APNs] No webhook secret — skipping token unregistration.")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(secret, forHTTPHeaderField: "X-Webhook-Token")
        let body: [String: String] = ["token": token]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                print("[APNs] Middleware unregistration error: \(error)")
            } else if let http = response as? HTTPURLResponse {
                print("[APNs] Middleware unregister responded: \(http.statusCode)")
            }
        }.resume()
    }

    /// The APNs environment this build ACTUALLY HOLDS, read from the embedded
    /// provisioning profile — not inferred from the build configuration.
    ///
    /// Ruled 2026-09-19 (Thomas). `#if DEBUG` was wrong in exactly the case
    /// nobody looks at: an Xcode **Release** install declares `production` while
    /// holding a `development` entitlement. APNs answered `400 BadDeviceToken`,
    /// 2.18.1's cleanup removed the token, and push died on the 13 Pro Max while
    /// the other phones kept working. Build configuration and entitlement are
    /// different things and they disagree precisely where nobody checks.
    ///
    /// **No profile means App Store, which means `production`.** A store build
    /// has no `embedded.mobileprovision` at all, so its absence is a fact rather
    /// than a guess — which is why every failure path below returns
    /// `production` rather than a "safe" default: on a released build, absent IS
    /// the correct answer, and on any other build the profile is present and
    /// readable.
    ///
    /// The file is CMS-signed; the payload is a plain XML plist inside it, so
    /// the plist is sliced out rather than the signature verified. Verifying it
    /// would add nothing: the file is inside our own signed bundle.
    static func apnsEnvironmentFromProvisioningProfile() -> String {
        guard let url = Bundle.main.url(forResource: "embedded",
                                        withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else {
            // The ONLY case that legitimately yields "production" without
            // reading it: a store build carries no profile at all.
            print("[APNs] No embedded.mobileprovision — App Store build, environment: production")
            return "production"
        }
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8),
                                   in: start.upperBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                  from: Data(data[start.lowerBound..<end.upperBound]),
                  format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let aps = entitlements["aps-environment"] as? String else {
            print("[APNs] embedded.mobileprovision present but aps-environment unreadable — DEFECT, registering as production")
            return "production"
        }
        print("[APNs] aps-environment from embedded.mobileprovision: \(aps)")
        return apnsEnvironment(forEntitlement: aps)
    }

    /// Translate the ENTITLEMENT's vocabulary into the MIDDLEWARE's.
    ///
    /// They are not the same words, and that cost a real installation on
    /// 2026-09-21: the first version of this fix read `aps-environment`
    /// correctly, sent the literal `development`, and `main.py:385` — which
    /// accepted only `sandbox`/`production` — silently stored it as
    /// **production**. So a `development` entitlement was registered as
    /// production again: exactly the defect this function exists to prevent,
    /// reintroduced one layer further along. Reading the right value is not
    /// enough; it has to be said in the language the other end speaks.
    ///
    /// | entitlement | APNs host | middleware |
    /// |---|---|---|
    /// | `development` | sandbox | `sandbox` |
    /// | `production` | production | `production` |
    ///
    /// **Anything else is a defect and is passed through unchanged, loudly.**
    /// It is not coerced to `production`: the middleware now refuses an
    /// unknown value with a 400, and a refused registration that says so is
    /// worth more than an accepted one that is wrong. `production` is returned
    /// without being read in exactly one case — no profile — and that case is
    /// handled by the caller above.
    ///
    /// Not `private`: BeNeMTests asserts it.
    static func apnsEnvironment(forEntitlement value: String) -> String {
        switch value {
        case "development": return "sandbox"
        case "production":  return "production"
        default:
            print("[APNs] DEFECT — unknown aps-environment \(value.isEmpty ? "<empty>" : value) — "
                  + "sending it unchanged; the middleware will refuse it")
            return value
        }
    }

    func registerWithMiddleware(token: String, secret: String, middlewareURL: String) {
        guard !middlewareURL.isEmpty, let url = URL(string: "\(middlewareURL)/register") else {
            print("[APNs] No middleware URL configured — skipping token registration.")
            return
        }
        guard !secret.isEmpty else {
            print("[APNs] No webhook secret for active connection — skipping token registration.")
            return
        }
        let apnsEnvironment = AppDelegate.apnsEnvironmentFromProvisioningProfile()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(secret, forHTTPHeaderField: "X-Webhook-Token")
        let body: [String: String] = [
            "token": token,
            "device_name": UIDevice.current.name,
            "environment": apnsEnvironment
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        print("[APNs] Registering with middleware (environment: \(apnsEnvironment))")
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
