import XCTest
@testable import BeNeM

/// The acknowledging user must be the **Username** typed into the admin portal's
/// QR generator — required there for exactly this reason, carried in the QR
/// payload as `user`, stored in `netreo_ack_user` and on the connection.
///
/// 2.13.4 replaced it with a constant, on the reasoning that values like
/// "Thomas iPhone 13 ProMax" looked like device names. The admin link log shows
/// they are the usernames someone typed. These tests exist so that mistake cannot
/// be repeated silently.
final class AckAttributionTests: XCTestCase {

    private func draft(ackUser: String) -> ServerDraft {
        ServerDraft(
            name: "Lab",
            middlewareURL: "https://mw.example",
            bhnmURL: "https://bhnm.example",
            apiKey: "key",
            pin: "",
            ackUser: ackUser,
            pushSecret: "",
            notificationsEnabled: false
        )
    }

    func testTheQRUsernameSurvivesOntoTheSavedConnection() {
        let conn = draft(ackUser: "Thomas iPhone 13 ProMax").connection()
        XCTAssertEqual(conn.ackUser, "Thomas iPhone 13 ProMax",
                       "the QR Username is what BHNM must record as the acknowledging user")
        XCTAssertNotEqual(conn.ackUser, NetreoAPIService.ackUserFallback,
                          "a constant must never displace a real username")
    }

    /// The form is closed; the QR path is not. `DeepLinkHandler` uses
    /// `(json["user"] as? String) ?? "enter user name"`, and an empty string IS a
    /// String — so a link carrying `"user": ""` yields an empty ackUser, bypassing
    /// `saveDisabled` entirely. The admin portal permits that: `user: str = Form("")`,
    /// required in JavaScript only. The fallback therefore fires on real input.
    func testAnEmptyUsernameBlocksSave_butOnlyThroughTheForm() {
        XCTAssertTrue(draft(ackUser: "").saveDisabled(isAddMode: true),
                      "the form requires a username, so an empty ackUser cannot be saved this way")
        XCTAssertTrue(draft(ackUser: "").saveDisabled(isAddMode: false),
                      "editing cannot empty it either")
        XCTAssertFalse(draft(ackUser: "Luiz").saveDisabled(isAddMode: true))
    }

    func testTheFallbackIsTheSameStringAsThePWA() {
        // pwa/src/lib/api/incidents.ts — ACK_USER_FALLBACK. If these drift, the two
        // clients attribute differently in the one case the fallback is used.
        XCTAssertEqual(NetreoAPIService.ackUserFallback, "BHNM Mobile")
    }
}
