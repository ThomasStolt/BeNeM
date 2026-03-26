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
        cachedDeviceToken = token
        let secret = activeWebhookSecret()
        registerWithMiddleware(token: token, secret: secret)
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

    func registerWithMiddleware(token: String, secret: String) {
        let middlewareURL = UserDefaults.standard.string(forKey: "push_middleware_url") ?? ""
        guard !middlewareURL.isEmpty, let url = URL(string: "\(middlewareURL)/register") else {
            print("[APNs] No middleware URL configured — skipping token registration.")
            return
        }
        guard !secret.isEmpty else {
            print("[APNs] No webhook secret for active connection — skipping token registration.")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(secret, forHTTPHeaderField: "X-Webhook-Token")
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

    private func activeWebhookSecret() -> String {
        let ud = UserDefaults.standard
        guard let activeID = ud.string(forKey: "netreo_active_connection_id"),
              !activeID.isEmpty else { return "" }
        let connections = ud.loadSavedConnections()
        return connections.first(where: { $0.id.uuidString == activeID })?.webhookSecret ?? ""
    }
}

extension Notification.Name {
    static let pushNotificationIncidentTapped = Notification.Name("PushNotificationIncidentTapped")
}
