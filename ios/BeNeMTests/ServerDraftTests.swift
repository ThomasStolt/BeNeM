// BeNeMTests/ServerDraftTests.swift
//
// Pure-logic tests for the server-config form. No SwiftUI, no snapshots, no UI tests.
// These exist because two data-loss-shaped questions in two days could only be
// answered by reading code — iOS is the platform where a defect is slowest and most
// expensive to fix, so it is the one that least deserves to be the untested one.
//
// They mirror the PWA tests in pwa/src/features/settings/__tests__/ServerForm.test.tsx
// so the two platforms cannot drift apart silently.
import XCTest
@testable import BeNeM

final class ServerDraftTests: XCTestCase {

    private func stored() -> ServerDraft {
        ServerDraft(name: "Original",
                    middlewareURL: "https://mw.example.com",
                    bhnmURL: "https://bhnm.example.com",
                    apiKey: "not-a-real-secret",
                    pin: "pin-1234",
                    ackUser: "thomas",
                    pushSecret: "not-a-real-webhook-secret",
                    notificationsEnabled: true)
    }

    /// THE DATA-LOSS TEST. Masking shows secrets as dots and the fields are editable,
    /// which together are the classic way to destroy a stored credential. Editing one
    /// unrelated field must round-trip every secret untouched.
    func testEditingAnUnrelatedFieldLeavesEverySecretUnchanged() {
        var draft = stored()
        draft.name = "Original-renamed"

        let saved = draft.connection()

        XCTAssertEqual(saved.name, "Original-renamed")
        XCTAssertEqual(saved.apiKey, "not-a-real-secret")
        XCTAssertEqual(saved.pin, "pin-1234")
        XCTAssertEqual(saved.webhookSecret, "not-a-real-webhook-secret")
    }

    /// The defect found on 2026-09-18: the save path wrote "" over the webhook secret
    /// whenever push was off, so toggling push off and on again silently destroyed it
    /// — and for a QR-provisioned connection the only recovery was a re-scan.
    func testTurningPushOffKeepsTheStoredSecret() {
        var draft = stored()
        draft.notificationsEnabled = false

        let saved = draft.connection()

        XCTAssertFalse(saved.notificationsEnabled, "the intent must still be recorded")
        XCTAssertEqual(saved.webhookSecret, "not-a-real-webhook-secret",
                       "a toggle must never clear a credential")
    }

    /// Clearing stays possible — it is just something the user does deliberately.
    func testEmptyingTheFieldStillClearsTheSecret() {
        var draft = stored()
        draft.pushSecret = ""
        XCTAssertEqual(draft.connection().webhookSecret, "")
    }

    /// A new validation rule must never trap data that already exists.
    func testExistingConnectionWithPushOnAndNoSecretIsStillEditable() {
        var draft = stored()
        draft.pushSecret = ""

        XCTAssertFalse(draft.saveDisabled(isAddMode: false),
                       "an existing connection must stay editable, or the user cannot "
                       + "fix anything else about it either")
        XCTAssertTrue(draft.saveDisabled(isAddMode: true),
                      "on ADD the secret is still required")
    }

    func testARequiredFieldStillBlocksSave() {
        var draft = stored()
        draft.apiKey = ""
        XCTAssertTrue(draft.saveDisabled(isAddMode: false))
    }

    /// Never reveal more than a quarter of a secret.
    func testTheMaskNeverRevealsMoreThanAQuarter() {
        XCTAssertEqual(ServerDraft.maskedSecret(""), "not set")
        // Below 16 characters: dots only. The last 4 of a 9-character key leaves 5 to
        // guess, which is not a display decision, it is a giveaway.
        XCTAssertEqual(ServerDraft.maskedSecret("short-key"), "••••••••")
        XCTAssertEqual(ServerDraft.maskedSecret("fifteen-chars-x"), "••••••••")
        // 16 or more: the last 4, never more, and never the whole value.
        XCTAssertEqual(ServerDraft.maskedSecret("not-a-real-secret"), "••••••••cret")
        XCTAssertEqual(ServerDraft.maskedSecret("not-a-real-secret-wxyz"), "••••••••wxyz")
        XCTAssertFalse(ServerDraft.maskedSecret("not-a-real-secret").contains("not-a"))
    }

    func testTheThresholdIsNotQuietlyLowered() {
        XCTAssertEqual(ServerDraft.secretRevealMinimumLength, 16,
                       "a quarter of 16 is 4. Lowering this to make a short key display "
                       + "nicely is the thing the rule exists to prevent.")
    }
}
