# API Proxy Middleware Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route all BeNeM API calls through the `bhnm-apns` middleware so BHNM servers on private networks are reachable from the internet.

**Architecture:** The iOS app points its `baseURL` at the middleware (deployed on-prem). The middleware authenticates requests via `X-Proxy-Token` (= `webhookSecret`) and transparently proxies them to the BHNM server on the LAN. Credentials pass through untouched. The existing push notification flow is unchanged.

**Tech Stack:** Swift/SwiftUI (iOS), Python/Quart/httpx (middleware), Python (generate_benem_link.py). Build verification with `xcodebuild`. Middleware is in a **separate repo** (`bhnm-apns`) — Tasks 10–11 apply there.

> **⚠️ Migration note:** Tasks 1–7 form a single atomic migration — removing `pushMiddlewareURL` from `SavedConnection` (Task 1) breaks the build until all dependent files are fixed. Each task commits its changes, but the build will only be fully green after Task 7 Step 6. Intermediate commits are fine; broken-build commits are expected between Tasks 1 and 7.

---

## File Map

| File | Change |
|---|---|
| `BeNeM/Models/SavedConnection.swift` | Remove `pushMiddlewareURL` field; no other changes |
| `BeNeM/AppDelegate.swift` | `activeConnectionPushCredentials()` returns `baseURL` not `pushMiddlewareURL` |
| `BeNeM/Services/NetreoAPIConfiguration.swift` | Add `proxyToken: String` field + init param |
| `BeNeM/Services/NetreoAPIService.swift` | Add `addProxyToken()` helper; call on all 15 request sites |
| `BeNeM/ContentView.swift` | Add `@AppStorage("netreo_webhook_secret")`; update `updateAPIService()` and `onChange(activeConnectionID)` |
| `BeNeM/Views/ServerConfigView.swift` | Remove `pushEnabled` toggle + `draftPushURL`; make webhook secret unconditional; update `saveConnection()`, `populateDrafts()`, `testAndSave()` |
| `BeNeM/Services/DeepLinkHandler.swift` | Remove `pushMiddlewareURL` from `PendingImport`; remove `push_url` reads/writes |
| `BeNeM/Views/AutoDiscoveryView.swift` | Remove connect-sheet auto-populate of `baseURL`; show BHNM IP as read-only |
| `generate_benem_link.py` | Rename `--bhnm-server` → `--middleware-url`; remove `--push-url`; update interactive mode |
| `bhnm-apns/app.py` (separate repo) | Add catch-all proxy route; add `BHNM_URL` / `BHNM_TLS_VERIFY` env vars; `httpx` dependency |

---

## Task 1: Remove `pushMiddlewareURL` from `SavedConnection`

**Files:**
- Modify: `BeNeM/Models/SavedConnection.swift`

- [ ] **Step 1: Read the file**

  Open `BeNeM/Models/SavedConnection.swift`. Confirm the struct has `pushMiddlewareURL: String = ""` on line 12.

- [ ] **Step 2: Remove the field**

  Delete line 12:
  ```
  var pushMiddlewareURL: String = ""  // per-connection push middleware; replaces global push_middleware_url
  ```

  The struct should now read:
  ```swift
  struct SavedConnection: Codable, Identifiable {
      let id: UUID
      var name: String
      var baseURL: String
      var apiKey: String
      var pin: String      // "" = absent
      var ackUser: String  // "" = absent
      var webhookSecret: String = ""
      var symbol: String = "server.rack"
      var accentColor: String = "#0A84FF"
  }
  ```

- [ ] **Step 3: Find all compiler errors caused by this removal**

  ```bash
  cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM
  xcodebuild -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | grep "error:" | grep -v "^Build"
  ```

  Expected: multiple errors referencing `pushMiddlewareURL` in `AppDelegate.swift`, `ContentView.swift`, `DeepLinkHandler.swift`, `ServerConfigView.swift`. **Do not fix them yet** — Tasks 2–7 fix each file. Note the line numbers. The build will remain broken until Task 7.

- [ ] **Step 4: Commit the struct change (build intentionally broken)**

  ```bash
  git add BeNeM/Models/SavedConnection.swift
  git commit -m "refactor: remove pushMiddlewareURL from SavedConnection — baseURL now serves both roles"
  ```

---

## Task 2: Update `AppDelegate` — use `baseURL` for push registration

**Files:**
- Modify: `BeNeM/AppDelegate.swift`

- [ ] **Step 1: Read `AppDelegate.swift`**

  Confirm `activeConnectionPushCredentials()` at line 109 returns `(conn.webhookSecret, conn.pushMiddlewareURL)`.

- [ ] **Step 2: Fix `activeConnectionPushCredentials()`**

  Change line 115 from:
  ```swift
  return (conn.webhookSecret, conn.pushMiddlewareURL)
  ```
  to:
  ```swift
  return (conn.webhookSecret, conn.baseURL)
  ```

- [ ] **Step 3: Build — this file's errors should now be gone**

  ```bash
  xcodebuild -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | grep -E "error:|Build succeeded"
  ```

  Expected: `AppDelegate.swift` no longer has errors. Remaining errors are in other files.

- [ ] **Step 4: Commit**

  ```bash
  git add BeNeM/AppDelegate.swift
  git commit -m "fix: activeConnectionPushCredentials uses baseURL (middleware) not pushMiddlewareURL"
  ```

---

## Task 3: Add `proxyToken` to `NetreoAPIConfiguration`

**Files:**
- Modify: `BeNeM/Services/NetreoAPIConfiguration.swift`

- [ ] **Step 1: Read `NetreoAPIConfiguration.swift`**

  Confirm the struct ends with `retryCount: Int` and its `init` ends with `retryCount: Int = 3`.

- [ ] **Step 2: Add `proxyToken` field**

  Add `let proxyToken: String` after `let retryCount: Int` in the struct, and `proxyToken: String = ""` as a new parameter in `init` before `version:`:

  ```swift
  struct NetreoAPIConfiguration {
      let baseURL: String
      let apiKey: String
      let pin: String?
      let proxyToken: String      // X-Proxy-Token value for middleware authentication
      let version: APIVersion
      let timeout: TimeInterval
      let retryCount: Int

      init(baseURL: String, apiKey: String, pin: String? = nil,
           proxyToken: String = "",
           version: APIVersion = .legacy,
           timeout: TimeInterval = 30,
           retryCount: Int = 3) {
          // ... existing normalisation logic unchanged ...
          self.proxyToken = proxyToken
      }
  }
  ```

- [ ] **Step 3: Build — no new errors should appear**

  ```bash
  xcodebuild -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | grep -E "error:|Build succeeded"
  ```

  Expected: no new errors (adding a defaulted param is backwards compatible).

- [ ] **Step 4: Commit**

  ```bash
  git add BeNeM/Services/NetreoAPIConfiguration.swift
  git commit -m "feat: add proxyToken to NetreoAPIConfiguration for X-Proxy-Token header"
  ```

---

## Task 4: Add `addProxyToken` to `NetreoAPIService` and apply to all request sites

**Files:**
- Modify: `BeNeM/Services/NetreoAPIService.swift`

This is the most mechanical task. There are 15 `var request = URLRequest(url:` sites in the file (lines 60, 89, 113, 130, 152, 217, 275, 310, 454, 507, 524, 618, 644, 678, 753).

- [ ] **Step 1: Add the helper method**

  Add this private method anywhere in the `NetreoAPIService` class body (e.g. just after `formEncodedBody`):

  ```swift
  private func addProxyToken(_ request: inout URLRequest) {
      guard !configuration.proxyToken.isEmpty else { return }
      request.setValue(configuration.proxyToken, forHTTPHeaderField: "X-Proxy-Token")
  }
  ```

- [ ] **Step 2: Apply the helper to every request**

  For each of the 15 `var request = URLRequest(url:` sites, add `addProxyToken(&request)` on the line immediately after `request.httpMethod = ...` is set (after the method is assigned, before any headers or body are set — consistency matters, but order within the setup block doesn't matter technically).

  Pattern to apply at every site:
  ```swift
  var request = URLRequest(url: url)
  request.httpMethod = "POST"
  addProxyToken(&request)          // ← add this line
  request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
  ```

  The two request sites that use `.GET` don't set a `Content-Type` — still add `addProxyToken(&request)` after `request.httpMethod`.

- [ ] **Step 3: Verify count — grep for the helper call**

  ```bash
  grep -c "addProxyToken" BeNeM/Services/NetreoAPIService.swift
  ```

  Expected output: `16` (1 definition + 15 call sites).

- [ ] **Step 4: Build**

  ```bash
  xcodebuild -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | grep -E "error:|Build succeeded"
  ```

  Expected: no errors in `NetreoAPIService.swift`.

- [ ] **Step 5: Commit**

  ```bash
  git add BeNeM/Services/NetreoAPIService.swift
  git commit -m "feat: inject X-Proxy-Token header on all API requests via addProxyToken helper"
  ```

---

## Task 5: Update `ContentView` — reactivity and `updateAPIService`

**Files:**
- Modify: `BeNeM/ContentView.swift`

- [ ] **Step 1: Read `ContentView.swift`**

  Confirm the `@AppStorage` declarations at lines 4–10, `updateAPIService()` at line 75, and the `onChange(activeConnectionID)` block at lines 43–54.

- [ ] **Step 2: Add `webhookSecret` AppStorage observer**

  Add this line after line 10 (`@AppStorage("netreo_active_connection_id")`):
  ```swift
  @AppStorage("netreo_webhook_secret") private var webhookSecret = ""
  ```

- [ ] **Step 3: Wire `webhookSecret` change to `updateAPIService`**

  Add this after the last existing `.onChange` at line 42:
  ```swift
  .onChange(of: webhookSecret) { _, _ in updateAPIService() }
  ```

- [ ] **Step 4: Pass `proxyToken` in `updateAPIService()`**

  In `updateAPIService()`, update the `NetreoAPIConfiguration` construction (lines 81–88) to add `proxyToken`:
  ```swift
  let configuration = NetreoAPIConfiguration(
      baseURL: baseURL,
      apiKey: apiKey,
      pin: pin.isEmpty ? nil : pin,
      proxyToken: webhookSecret,
      version: apiVersion,
      timeout: timeout,
      retryCount: Int(retryCount)
  )
  ```

- [ ] **Step 5: Fix `onChange(activeConnectionID)` — use `baseURL` not `pushMiddlewareURL`**

  Change line 51 from:
  ```swift
  middlewareURL: conn.pushMiddlewareURL
  ```
  to:
  ```swift
  middlewareURL: conn.baseURL
  ```

  Also add a line to keep `netreo_webhook_secret` current when switching connections (add before the `registerWithMiddleware` call):
  ```swift
  UserDefaults.standard.set(conn.webhookSecret, forKey: "netreo_webhook_secret")
  ```

  > **Why this works:** Writing to `netreo_webhook_secret` via UserDefaults updates the `@AppStorage("netreo_webhook_secret") private var webhookSecret` property added in Step 2. SwiftUI observes this change and fires the `.onChange(of: webhookSecret)` added in Step 3, which calls `updateAPIService()`. The live `NetreoAPIService` is rebuilt with the new `proxyToken` — no stale token after a connection switch.

- [ ] **Step 6: Build**

  ```bash
  xcodebuild -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | grep -E "error:|Build succeeded"
  ```

  Expected: `ContentView.swift` errors resolved.

- [ ] **Step 7: Commit**

  ```bash
  git add BeNeM/ContentView.swift
  git commit -m "feat: wire webhookSecret to updateAPIService and fix onChange to use baseURL"
  ```

---

## Task 6: Overhaul `ServerConfigView` — remove toggle, make secret unconditional

**Files:**
- Modify: `BeNeM/Views/ServerConfigView.swift`

- [ ] **Step 1: Read `ServerConfigView.swift`**

  Confirm the draft state (lines 14–24), the Push Notifications section (lines 96–110), `populateDrafts()` (lines 174–188), `saveConnection()` (lines 283–312), and the `disabled(...)` condition (line 132).

- [ ] **Step 2: Remove `pushEnabled` and `draftPushURL` draft state**

  Delete lines 22–23:
  ```swift
  @State private var pushEnabled     = false
  @State private var draftPushURL    = ""
  ```

  Also remove `.pushURL` from the `Field` enum at line 37:
  ```swift
  private enum Field: Hashable { case name, url, apiKey, pin, ackUser, pushSecret }
  ```

- [ ] **Step 3: Replace the "Push Notifications" section**

  Replace the entire `Section("Push Notifications")` block (lines 96–110) with:
  ```swift
  Section("Push Notifications") {
      LabeledField("Webhook Secret", placeholder: "Required for middleware connection") {
          SecureField("", text: $draftPushSecret)
              .focused($focusedField, equals: .pushSecret)
      }
      Text("Enter the webhook secret configured in your middleware's .env file.")
          .font(.caption)
          .foregroundColor(.secondary)
  }
  ```

- [ ] **Step 4: Update `populateDrafts()` — remove gated push logic**

  Replace the push-related lines in `populateDrafts()` (lines 184–186):
  ```swift
  // Remove these three lines:
  draftPushURL    = conn.pushMiddlewareURL
  draftPushSecret = conn.webhookSecret
  pushEnabled     = !conn.pushMiddlewareURL.isEmpty || !conn.webhookSecret.isEmpty
  ```
  with:
  ```swift
  draftPushSecret = conn.webhookSecret
  ```

- [ ] **Step 5: Update `saveConnection()` — remove `pushEnabled` gate and `pushMiddlewareURL`**

  In `saveConnection()` (around line 285–296), replace the `SavedConnection` construction literal. Change:
  ```swift
  webhookSecret: pushEnabled ? draftPushSecret.trimmingCharacters(in: .whitespacesAndNewlines) : "",
  pushMiddlewareURL: pushEnabled ? draftPushURL.trimmingCharacters(in: .whitespacesAndNewlines) : "",
  ```
  with:
  ```swift
  webhookSecret: draftPushSecret.trimmingCharacters(in: .whitespacesAndNewlines),
  ```

  After `UserDefaults.standard.saveSavedConnections(savedConnections)` (line 302), add the write to `netreo_webhook_secret` so `ContentView` reacts:
  ```swift
  UserDefaults.standard.saveSavedConnections(savedConnections)
  // Keep netreo_webhook_secret in sync so ContentView.updateAPIService() fires
  if isAddMode || existingConnection?.id.uuidString == activeSavedConnectionID {
      UserDefaults.standard.set(now.webhookSecret, forKey: "netreo_webhook_secret")
  }
  ```

- [ ] **Step 6: Update `testAndSave()` — add `X-Proxy-Token` header**

  After line 221 (`request.httpMethod = "POST"`), add:
  ```swift
  if !draftPushSecret.isEmpty {
      request.setValue(draftPushSecret, forHTTPHeaderField: "X-Proxy-Token")
  }
  ```

- [ ] **Step 7: Update the `disabled(...)` condition — require non-empty secret**

  Change line 132 from:
  ```swift
  .disabled(isTesting || draftBaseURL.isEmpty || draftApiKey.isEmpty || draftName.isEmpty || draftAckUser.isEmpty)
  ```
  to:
  ```swift
  .disabled(isTesting || draftBaseURL.isEmpty || draftApiKey.isEmpty || draftName.isEmpty || draftAckUser.isEmpty || draftPushSecret.isEmpty)
  ```

- [ ] **Step 8: Rename "Server URL" label to "Middleware URL"**

  Change line 74:
  ```swift
  LabeledField("Server URL", placeholder: "bhnm.example.com") {
  ```
  to:
  ```swift
  LabeledField("Middleware URL", placeholder: "https://bhnm-apns.yourcompany.com") {
  ```

- [ ] **Step 9: Build**

  ```bash
  xcodebuild -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | grep -E "error:|Build succeeded"
  ```

  Expected: `ServerConfigView.swift` errors resolved.

- [ ] **Step 10: Commit**

  ```bash
  git add BeNeM/Views/ServerConfigView.swift
  git commit -m "feat: remove pushEnabled toggle, webhook secret now unconditional and required for all API calls"
  ```

---

## Task 7: Update `DeepLinkHandler` — remove `pushMiddlewareURL`

**Files:**
- Modify: `BeNeM/Services/DeepLinkHandler.swift`

- [ ] **Step 1: Read `DeepLinkHandler.swift`**

  Confirm `PendingImport` at lines 8–18, `handleCompactPayload` at line 166, and `applyPendingImport()` at line 82.

- [ ] **Step 2: Remove `pushMiddlewareURL` from `PendingImport`**

  Delete line 14 from the struct:
  ```swift
  let pushMiddlewareURL: String // "" if absent; replaces old pushURL field
  ```

- [ ] **Step 3: Fix `handleCompactPayload` — remove `push_url` read**

  In `handleCompactPayload` (around line 183), change the `PendingImport(...)` construction. Remove:
  ```swift
  pushMiddlewareURL: str("push_url"),
  ```
  The field no longer exists.

- [ ] **Step 4: Fix legacy format handler — ignore `push_url`**

  In the legacy `handle(url:)` path (around lines 55–76), delete the line:
  ```swift
  let pushURL = param("push_url") ?? ""
  ```
  And remove `pushMiddlewareURL: pushURL,` from the `PendingImport(...)` construction.

- [ ] **Step 5: Fix `applyPendingImport()` — remove all three `pushMiddlewareURL` sites**

  There are three sites to fix in `applyPendingImport()`:

  **Site 1** — update-existing block (lines 106–108). Remove:
  ```swift
  if !imp.pushMiddlewareURL.isEmpty {
      connections[idx].pushMiddlewareURL = imp.pushMiddlewareURL
  }
  ```

  **Site 2** — new-entry `SavedConnection` construction (line 123). Remove:
  ```swift
  pushMiddlewareURL: imp.pushMiddlewareURL,
  ```

  **Site 3** — `registerWithMiddleware` call (lines 139–143). Change `middlewareURL: conn.pushMiddlewareURL` to `middlewareURL: conn.baseURL`:
  ```swift
  AppDelegate.shared?.registerWithMiddleware(
      token: token,
      secret: conn.webhookSecret,
      middlewareURL: conn.baseURL
  )
  ```

- [ ] **Step 6: Build**

  ```bash
  xcodebuild -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | grep -E "error:|Build succeeded"
  ```

  Expected: `DeepLinkHandler.swift` errors resolved.

- [ ] **Step 7: Confirm no remaining `pushMiddlewareURL` references**

  ```bash
  grep -r "pushMiddlewareURL" BeNeM/
  ```

  Expected: no output.

- [ ] **Step 8: Commit**

  ```bash
  git add BeNeM/Services/DeepLinkHandler.swift
  git commit -m "refactor: remove pushMiddlewareURL from DeepLinkHandler — baseURL is the middleware URL"
  ```

---

## Task 8: Update `AutoDiscoveryView` — remove direct `baseURL` write

**Files:**
- Modify: `BeNeM/Views/AutoDiscoveryView.swift`

- [ ] **Step 1: Read the rest of `AutoDiscoveryView.swift`**

  Read from line 119 onward to find the `connectSheet` computed property and all write sites (`baseURL = server.baseURL`, `apiKey = apiKeyInput`).

- [ ] **Step 2: Remove the connect-sheet code FIRST (before removing `@AppStorage`)**

  > **Order matters:** the `connectSheet` property writes `baseURL` and `apiKey`. Remove it before removing the `@AppStorage` declarations, or the compiler will error on `baseURL` references that no longer exist.

  Remove in this order:
  - The `.sheet(isPresented: $showConnectSheet)` modifier from `body`
  - The `.overlay` success banner block from `body`
  - The `connectSheet` computed property entirely
  - The `.swipeActions` block in `serverRow`
  - The `.onTapGesture` in `serverRow`

- [ ] **Step 3: Update `serverRow` to show a read-only info label**

  Replace the existing `serverRow` `VStack` content with:
  ```swift
  VStack(alignment: .leading, spacing: 4) {
      Text(server.ip)
          .font(.headline)
          .foregroundColor(.primary)
      Text(server.sysDescr)
          .font(.caption)
          .foregroundColor(.secondary)
          .lineLimit(2)
      Text("Enter this address as Middleware URL in Settings → Add/Edit Server.")
          .font(.caption2)
          .foregroundColor(.secondary)
          .padding(.top, 2)
  }
  .padding(.vertical, 2)
  ```

- [ ] **Step 4: Remove `@AppStorage` declarations and unused state**

  Now that no code references `baseURL` or `apiKey`, remove:
  ```swift
  @AppStorage("netreo_base_url") private var baseURL = ""
  @AppStorage("netreo_api_key") private var apiKey = ""
  ```
  And remove unreferenced `@State` variables: `connectingServer`, `apiKeyInput`, `showConnectSheet`, `showSuccessBanner`.

- [ ] **Step 6: Build**

  ```bash
  xcodebuild -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | grep -E "error:|Build succeeded"
  ```

  Expected: `Build succeeded`.

- [ ] **Step 7: Deploy and manually verify**

  ```bash
  ./build_and_deploy.sh
  ```

  Open AutoDiscovery in Settings. Scan should work. Discovered servers should appear as read-only info cards. No connect button or sheet should appear.

- [ ] **Step 8: Commit**

  ```bash
  git add BeNeM/Views/AutoDiscoveryView.swift
  git commit -m "feat: AutoDiscovery now read-only — shows BHNM IP for reference, no direct connect"
  ```

---

## Task 9: Update `generate_benem_link.py` — remove `push_url`, rename `bhnm-server`

**Files:**
- Modify: `generate_benem_link.py`

- [ ] **Step 1: Read `generate_benem_link.py`**

  Confirm `--bhnm-server` at line 130, `--push-url` at line 139, and the interactive mode `push_url` prompts at lines 95–100.

- [ ] **Step 2: Rename `--bhnm-server` to `--middleware-url`**

  Change line 130–131:
  ```python
  parser.add_argument("--bhnm-server", dest="server",
                      help="BHNM server URL (e.g. https://bhnm.example.com)")
  ```
  to:
  ```python
  parser.add_argument("--middleware-url", dest="server",
                      help="Middleware URL (e.g. https://bhnm-apns.yourcompany.com)")
  ```

  Update the error message at line 152:
  ```python
  parser.error("--middleware-url and --api_key are required (or use -i for interactive mode)")
  ```

- [ ] **Step 3: Remove `--push-url` argument**

  Delete lines 139–141:
  ```python
  parser.add_argument("--push-url", dest="push_url", default="",
                      help="Push middleware URL (encrypted in payload)")
  ```

  Remove `"push_url": args.push_url,` from the `payload` dict at line 162.

- [ ] **Step 4: Update interactive mode**

  In `interactive_mode()` (lines 66–112):
  - Change `prompt("BHNM Server URL")` to `prompt("Middleware URL")`.
  - Remove the `push_url` prompt block (lines 95–100):
    ```python
    # Remove these lines entirely:
    push_url = ""
    push_secret = ""
    enable_push = prompt("Enable push notifications? [y/N]").lower() == "y"
    if enable_push:
        push_url = prompt("  Middleware URL")
        push_secret = prompt("  Webhook Secret", secret=True)
    ```
    Replace with:
    ```python
    push_secret = prompt("Webhook Secret", secret=True)
    ```
  - Remove `"push_url": push_url,` from the returned dict (line 108).

- [ ] **Step 5: Verify the script runs**

  ```bash
  python3 generate_benem_link.py --help
  ```

  Expected: help text shows `--middleware-url`, no `--push-url` or `--bhnm-server`.

- [ ] **Step 6: Commit**

  ```bash
  git add generate_benem_link.py
  git commit -m "feat: rename --bhnm-server to --middleware-url, remove --push-url from deep link generator"
  ```

---

## Task 10: Middleware — add proxy route to `bhnm-apns` *(separate repo)*

> This task is performed in the **`bhnm-apns`** repository, not BeNeM. Clone or open it separately.

**Files (in `bhnm-apns` repo):**
- Modify: `app.py` (or equivalent main application file)
- Modify: `.env.example`
- Modify: `requirements.txt`

- [ ] **Step 1: Add `httpx` to `requirements.txt`**

  ```
  httpx
  ```

- [ ] **Step 2: Add env vars to `.env.example`**

  ```bash
  # BHNM server on the local network — no trailing slash
  BHNM_URL=http://192.168.x.x
  # Set to false if BHNM uses a self-signed TLS certificate
  BHNM_TLS_VERIFY=true
  ```

- [ ] **Step 3: Add constants at the top of `app.py`** (after existing env var reads)

  ```python
  import httpx

  HOP_BY_HOP_REQUEST = {
      "host", "x-proxy-token", "connection", "keep-alive",
      "proxy-authenticate", "proxy-authorization", "te", "trailers", "upgrade"
  }
  HOP_BY_HOP_RESPONSE = {
      "connection", "keep-alive", "proxy-authenticate",
      "proxy-authorization", "te", "trailers", "transfer-encoding", "upgrade"
  }

  BHNM_URL = os.getenv("BHNM_URL", "").rstrip("/")
  BHNM_TLS_VERIFY = os.getenv("BHNM_TLS_VERIFY", "true").lower() != "false"
  ```

- [ ] **Step 4: Add catch-all proxy route** — register this **after** the existing `/register` and `/webhook` routes so they take priority

  ```python
  @app.route("/<path:path>", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])
  async def proxy(path):
      token = request.headers.get("X-Proxy-Token", "")
      if token != WEBHOOK_SECRET:
          return {"error": "Unauthorized"}, 401

      if not BHNM_URL:
          return {"error": "BHNM_URL not configured"}, 503

      target = f"{BHNM_URL}/{path}"
      if request.query_string:
          target += f"?{request.query_string.decode()}"

      forward_headers = {
          k: v for k, v in request.headers
          if k.lower() not in HOP_BY_HOP_REQUEST
      }

      async with httpx.AsyncClient(verify=BHNM_TLS_VERIFY) as client:
          resp = await client.request(
              method=request.method,
              url=target,
              headers=forward_headers,
              content=await request.get_data(),
          )

      response_headers = {
          k: v for k, v in resp.headers.items()
          if k.lower() not in HOP_BY_HOP_RESPONSE
      }

      return resp.content, resp.status_code, response_headers
  ```

- [ ] **Step 5: Add `BHNM_URL` to `.env`**

  In the actual `.env` file (not committed to git):
  ```
  BHNM_URL=http://<your-bhnm-server-ip>
  BHNM_TLS_VERIFY=true
  ```

- [ ] **Step 6: Test locally**

  ```bash
  pip install httpx
  # Start the middleware
  python app.py
  # In another terminal, test that the proxy rejects without a token
  curl -s -o /dev/null -w "%{http_code}" http://localhost:<port>/fw/index.php?r=restful/devices/list
  # Expected: 401
  # Test with correct token
  curl -s -o /dev/null -w "%{http_code}" \
    -H "X-Proxy-Token: <your-webhook-secret>" \
    -X POST http://localhost:<port>/fw/index.php?r=restful/devices/list \
    -d "password=<api-key>"
  # Expected: same response as calling BHNM directly
  ```

- [ ] **Step 7: Rebuild and deploy Docker container**

  ```bash
  docker compose build
  docker compose up -d
  ```

- [ ] **Step 8: Commit in the `bhnm-apns` repo**

  ```bash
  git add app.py requirements.txt .env.example
  git commit -m "feat: add catch-all proxy route for BeNeM API calls with X-Proxy-Token auth"
  ```

---

## Task 11: End-to-end verification

- [ ] **Step 1: Configure a connection in the app**

  In Settings → Add Server:
  - "Middleware URL": `https://bhnm-apns.yourcompany.com` (the deployed middleware)
  - API Token: your BHNM API key
  - Webhook Secret: the `WEBHOOK_SECRET` from the middleware `.env`
  - User Name: your ACK username

  Tap "Test & Save". Expected: the test proxies through middleware to BHNM and succeeds (device list returns > 0 devices).

- [ ] **Step 2: Verify all tabs load data**

  Navigate to Dashboard, Incidents, Devices. All should load data. Check the middleware logs to confirm requests are arriving and being forwarded.

- [ ] **Step 3: Verify push registration uses the right URL**

  Check middleware logs for a `POST /register` call. The `middlewareURL` logged should be the middleware's own base URL (not a BHNM IP).

- [ ] **Step 4: Verify a 401 is surfaced correctly**

  Temporarily set an incorrect Webhook Secret in Settings. Tap refresh. The app should show a connection error (not a silent failure or crash).

- [ ] **Step 5: Final build and deploy**

  ```bash
  ./build_and_deploy.sh
  ```

---

## Migration Note for Users

Existing users must:
1. Update their BHNM server middleware (`docker compose pull && docker compose up -d`) to pick up the proxy route.
2. In Settings, edit each saved connection and change the "Middleware URL" field from the BHNM server address to the middleware URL.
3. Ensure a Webhook Secret is set — the Save button will not work without one.
4. Regenerate any `benem://` deep links using the updated `generate_benem_link.py --middleware-url` flag.
