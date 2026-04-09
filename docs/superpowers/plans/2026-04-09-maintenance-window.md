# Maintenance Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Create Maintenance Window" button and dialog to device detail views on iOS and PWA, proxied through the middleware to BHNM.

**Architecture:** Apps send device name, duration (minutes), and comment to a new middleware endpoint. The middleware calculates UTC start/end timestamps (start = now + 15 min, end = start + duration) and forwards to BHNM's `maint_window_api.php`. No state stored in the middleware.

**Tech Stack:** Python/FastAPI (middleware), Swift/SwiftUI (iOS), React/TypeScript (PWA)

**Spec:** `docs/superpowers/specs/2026-04-09-maintenance-window-design.md`

---

## File Structure

| Action | File | Responsibility |
|---|---|---|
| Modify | `middleware/main.py` | New `/api/proxy/maintenance/create` endpoint |
| Create | `middleware/tests/test_maintenance.py` | Middleware endpoint tests |
| Modify | `ios/BeNeM/Services/NetreoAPIService.swift` | New `createMaintenanceWindow()` method |
| Create | `ios/BeNeM/Views/MaintenanceWindowSheet.swift` | SwiftUI sheet with duration picker + description |
| Modify | `ios/BeNeM/Views/DeviceDetailView.swift` | Add maintenance button + sheet trigger |
| Create | `pwa/src/lib/api/maintenance.ts` | `createMaintenanceWindow()` API function |
| Create | `pwa/src/features/devices/MaintenanceDialog.tsx` | React modal dialog component |
| Modify | `pwa/src/features/devices/DeviceDetailScreen.tsx` | Add maintenance button + dialog trigger |
| Modify | `shared/BHNM_API_REFERENCE.md` | Document the `maint_window_api.php` endpoint |

---

### Task 1: Document the BHNM Maintenance API

**Files:**
- Modify: `shared/BHNM_API_REFERENCE.md`

- [ ] **Step 1: Add the maintenance window API section**

Append before the "Open 3.0 API — Quick Reference" section at the end of the file:

```markdown
## Maintenance Window API

Creates or closes one-time maintenance windows for a device. Discovered by
inspecting the BHNM server source (`/home/httpd/html/api/maint_window_api.php`).

```
POST https://YOUR_HOST/api/maint_window_api.php
```

Auth: `password=` (same as Legacy API).

### Actions

#### Create a maintenance window (`action=new`)

| Parameter | Required | Notes |
|---|---|---|
| `password` | yes | API password |
| `action` | yes | `new` |
| `name` | yes | Device name (string, not numeric ID) |
| `start_time` | yes | UTC Unix timestamp. Must be in the future (`> time()`). |
| `end_time` | yes | UTC Unix timestamp. Must be > `start_time`. |
| `comment` | no | Description text (stored in `maintenance_window_log.description`) |

Response:
```json
{"result": "completed", "detail": "Maintenance window setting has been added"}
```

**Note:** `author_name` is hardcoded to `"api_user"` by the endpoint. Use the
`comment` field to record who requested the window.

**Note:** BHNM's built-in UI schedules maintenance windows to start 15 minutes
in the future. BeNeM follows the same convention.

#### Close all maintenance windows (`action=close`)

| Parameter | Required | Notes |
|---|---|---|
| `password` | yes | API password |
| `action` | yes | `close` |
| `name` | yes | Device name |

Response:
```json
{"result": "completed", "detail": "All maintenance windows for this device are closed"}
```

### Example — create a 1-hour maintenance window:
```bash
START=$(( $(date +%s) + 900 )); END=$(( START + 3600 )); \
curl --request POST \
  --url 'https://YOUR_HOST/api/maint_window_api.php' \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data "password=YOUR_PASSWORD&action=new&name=raspi-050&start_time=$START&end_time=$END&comment=Scheduled+via+API"
```
```

Also add to the Quick Reference table at the bottom of the file:

```markdown
| Create maintenance window | `POST /api/maint_window_api.php` | `password=` |
```

- [ ] **Step 2: Commit**

```bash
git add shared/BHNM_API_REFERENCE.md
git commit -m "docs: add BHNM maintenance window API to reference"
```

---

### Task 2: Middleware — Maintenance Create Endpoint

**Files:**
- Modify: `middleware/main.py:536-551` (insert after existing proxy routes)
- Create: `middleware/tests/test_maintenance.py`

- [ ] **Step 1: Write the test file**

Create `middleware/tests/test_maintenance.py`:

```python
import os
os.environ.setdefault("APNS_KEY_ID", "test")
os.environ.setdefault("APNS_TEAM_ID", "test")
os.environ.setdefault("APNS_BUNDLE_ID", "com.test")
os.environ.setdefault("APNS_PRIVATE_KEY_B64", "ZHVtbXk=")
os.environ.setdefault("DB_PATH", "/tmp/test_maintenance.db")
os.environ.setdefault("SERVERS_JSON_PATH", "/tmp/test_maint_servers.json")

import json
import time
from unittest.mock import AsyncMock, patch

import pytest
from fastapi.testclient import TestClient
from main import app


@pytest.fixture(autouse=True)
def setup_servers(tmp_path):
    servers_file = tmp_path / "servers.json"
    servers_file.write_text(json.dumps([
        {"id": "prod", "name": "Prod", "url": "https://bhnm.example.com", "api_key": "secret-key-123"}
    ]))
    import main as main_mod
    original_path = main_mod.SERVERS_JSON_PATH
    original_proxy_token = main_mod.PROXY_TOKEN
    main_mod.SERVERS_JSON_PATH = str(servers_file)
    main_mod.PROXY_TOKEN = ""
    yield
    main_mod.SERVERS_JSON_PATH = original_path
    main_mod.PROXY_TOKEN = original_proxy_token


@pytest.fixture
def client():
    return TestClient(app)


def test_maintenance_rejects_missing_token(client):
    resp = client.post("/api/proxy/maintenance/create", data={
        "name": "raspi-050", "duration": "60", "comment": "test",
    })
    assert resp.status_code == 401


def test_maintenance_rejects_missing_name(client):
    resp = client.post("/api/proxy/maintenance/create",
        headers={"X-Proxy-Token": "secret-key-123"},
        data={"duration": "60", "comment": "test"})
    assert resp.status_code == 400
    assert "name" in resp.json()["detail"].lower()


def test_maintenance_rejects_missing_duration(client):
    resp = client.post("/api/proxy/maintenance/create",
        headers={"X-Proxy-Token": "secret-key-123"},
        data={"name": "raspi-050", "comment": "test"})
    assert resp.status_code == 400
    assert "duration" in resp.json()["detail"].lower()


def test_maintenance_rejects_invalid_duration(client):
    resp = client.post("/api/proxy/maintenance/create",
        headers={"X-Proxy-Token": "secret-key-123"},
        data={"name": "raspi-050", "duration": "0", "comment": "test"})
    assert resp.status_code == 400


def test_maintenance_rejects_non_numeric_duration(client):
    resp = client.post("/api/proxy/maintenance/create",
        headers={"X-Proxy-Token": "secret-key-123"},
        data={"name": "raspi-050", "duration": "abc", "comment": "test"})
    assert resp.status_code == 400


@patch("main.httpx.AsyncClient")
def test_maintenance_forwards_to_bhnm(mock_client_cls, client):
    mock_response = AsyncMock()
    mock_response.status_code = 200
    mock_response.content = b'{"result":"completed","detail":"Maintenance window setting has been added"}'
    mock_response.headers = {"content-type": "application/json"}

    mock_client = AsyncMock()
    mock_client.request = AsyncMock(return_value=mock_response)
    mock_client.__aenter__ = AsyncMock(return_value=mock_client)
    mock_client.__aexit__ = AsyncMock(return_value=None)
    mock_client_cls.return_value = mock_client

    now = int(time.time())
    resp = client.post("/api/proxy/maintenance/create",
        headers={"X-Proxy-Token": "secret-key-123"},
        data={"name": "raspi-050", "duration": "60", "comment": "test maint"})

    assert resp.status_code == 200
    assert resp.json()["result"] == "completed"

    # Verify the forwarded request
    call_kwargs = mock_client.request.call_args
    assert "/api/maint_window_api.php" in call_kwargs.kwargs["url"]
    body = call_kwargs.kwargs["content"].decode()
    assert "action=new" in body
    assert "name=raspi-050" in body
    assert "comment=test+maint" in body
    # start_time should be ~now+900
    import re
    st_match = re.search(r"start_time=(\d+)", body)
    et_match = re.search(r"end_time=(\d+)", body)
    assert st_match and et_match
    start_time = int(st_match.group(1))
    end_time = int(et_match.group(1))
    assert abs(start_time - (now + 900)) < 5  # within 5 seconds
    assert end_time == start_time + 3600  # 60 minutes
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd middleware && python -m pytest tests/test_maintenance.py -v`
Expected: FAIL — endpoint does not exist yet.

- [ ] **Step 3: Add the maintenance endpoint to main.py**

Insert after the `proxy_ha_status` route (after line 551 in `middleware/main.py`), before the catch-all proxy section:

```python
@app.post("/api/proxy/maintenance/create")
async def proxy_maintenance_create(request: Request):
    """Create a maintenance window on BHNM for a device."""
    _verify_proxy_token(request)
    body = await request.body()
    parsed = parse_qs(body.decode("utf-8", errors="replace"))

    name = (parsed.get("name") or [None])[0]
    duration_str = (parsed.get("duration") or [None])[0]
    comment = (parsed.get("comment") or [""])[0]

    if not name:
        raise HTTPException(status_code=400, detail="Missing required field: name")
    if not duration_str:
        raise HTTPException(status_code=400, detail="Missing required field: duration")
    try:
        duration = int(duration_str)
    except ValueError:
        raise HTTPException(status_code=400, detail="Duration must be a number (minutes)")
    if duration < 1:
        raise HTTPException(status_code=400, detail="Duration must be at least 1 minute")

    start_time = int(time.time()) + 900  # now + 15 minutes
    end_time = start_time + (duration * 60)

    # Resolve BHNM target server
    target_base = request.headers.get("X-BHNM-Target", "").strip().rstrip("/")
    if not target_base:
        api_key = parsed.get("password", [""])[0]
        if api_key:
            target_base = _target_for_api_key(api_key)
    if not target_base:
        cfg = _resolve_server_config(request)
        if cfg:
            target_base = cfg.get("url", "").rstrip("/")
    if not target_base:
        target_base = _single_server_url()
    if not target_base:
        raise HTTPException(status_code=502, detail="Bad Gateway: BHNM target server not configured")
    _validate_proxy_target(target_base)

    target = f"{target_base}/api/maint_window_api.php"

    # Build the form body for BHNM
    api_key = parsed.get("password", [""])[0]
    if not api_key:
        cfg = _resolve_server_config(request)
        if cfg:
            api_key = cfg.get("api_key", "")
    maint_params = {
        "password": api_key,
        "action": "new",
        "name": name,
        "start_time": str(start_time),
        "end_time": str(end_time),
        "comment": comment,
    }
    forward_body = "&".join(f"{k}={v}" for k, v in maint_params.items())

    forward_headers = {
        "content-type": "application/x-www-form-urlencoded",
    }

    print(f"[Proxy] Maintenance create: device={name}, duration={duration}min, start={start_time}, end={end_time}")

    try:
        async with httpx.AsyncClient(verify=BHNM_TLS_VERIFY, timeout=PROXY_TIMEOUT) as client:
            resp = await client.request(
                method="POST",
                url=target,
                headers=forward_headers,
                content=forward_body.encode(),
            )
    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail="Gateway Timeout: BHNM server did not respond in time")
    except httpx.ConnectError:
        raise HTTPException(status_code=502, detail="Bad Gateway: could not connect to BHNM server")
    except httpx.RequestError as exc:
        print(f"[Proxy] Maintenance request error: {exc}")
        raise HTTPException(status_code=502, detail="Bad Gateway: request to BHNM server failed")

    response_headers = {
        k: v for k, v in resp.headers.items()
        if k.lower() not in HOP_BY_HOP_RESPONSE
    }
    return Response(content=resp.content, status_code=resp.status_code, headers=response_headers)
```

Also add `import time` at the top of `main.py` if not already present, and ensure `from urllib.parse import parse_qs` is imported (check existing imports).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd middleware && python -m pytest tests/test_maintenance.py -v`
Expected: All 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add middleware/main.py middleware/tests/test_maintenance.py
git commit -m "feat(middleware): add /api/proxy/maintenance/create endpoint"
```

---

### Task 3: iOS — API Service Method

**Files:**
- Modify: `ios/BeNeM/Services/NetreoAPIService.swift:777` (insert after `unacknowledgeIncident`)

- [ ] **Step 1: Add createMaintenanceWindow method**

Insert after the `unacknowledgeIncident` method (around line 777) in `NetreoAPIService.swift`:

```swift
    // MARK: - Maintenance Window

    func createMaintenanceWindow(deviceName: String, durationMinutes: Int, comment: String) async throws -> Bool {
        guard let url = URL(string: "\(configuration.baseURL)/api/proxy/maintenance/create") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addProxyToken(&request)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = [
            URLQueryItem(name: "password", value: configuration.apiKey),
            URLQueryItem(name: "name", value: deviceName),
            URLQueryItem(name: "duration", value: String(durationMinutes)),
            URLQueryItem(name: "comment", value: comment),
        ]
        if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
        request.httpBody = formEncodedBody(params)
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        if httpResponse.statusCode >= 400 { return false }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let result = json["result"] as? String {
            return result == "completed"
        }
        return false
    }
```

- [ ] **Step 2: Build to verify compilation**

Run: `cd ios && xcodebuild -scheme BeNeM -destination 'platform=iOS,name=TomiPhone13' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add ios/BeNeM/Services/NetreoAPIService.swift
git commit -m "feat(ios): add createMaintenanceWindow API method"
```

---

### Task 4: iOS — Maintenance Window Sheet

**Files:**
- Create: `ios/BeNeM/Views/MaintenanceWindowSheet.swift`

- [ ] **Step 1: Create the sheet view**

Create `ios/BeNeM/Views/MaintenanceWindowSheet.swift`:

```swift
import SwiftUI

struct MaintenanceWindowSheet: View {
    let deviceName: String
    let apiService: NetreoAPIService
    let onDismiss: () -> Void

    @State private var selectedDuration: DurationOption = .oneHour
    @State private var customMinutes: String = "60"
    @State private var comment: String = ""
    @State private var isCreating = false
    @State private var showResult: ResultType?

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
        _comment = State(initialValue: "set by api_user on \(formatter.string(from: Date()))")
    }

    private var durationMinutes: Int {
        if let fixed = selectedDuration.minutes { return fixed }
        return Int(customMinutes) ?? 60
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

                Section("Description") {
                    TextField("Description", text: $comment)
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

- [ ] **Step 2: Build to verify compilation**

Run: `cd ios && xcodebuild -scheme BeNeM -destination 'platform=iOS,name=TomiPhone13' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add ios/BeNeM/Views/MaintenanceWindowSheet.swift
git commit -m "feat(ios): add MaintenanceWindowSheet view"
```

---

### Task 5: iOS — Wire Sheet into DeviceDetailView

**Files:**
- Modify: `ios/BeNeM/Views/DeviceDetailView.swift`

- [ ] **Step 1: Add state and button to DeviceDetailView**

Add a `@State` property at the top of `DeviceDetailView` (after the `@StateObject` line):

```swift
    @State private var showMaintenanceSheet = false
```

Add a `.toolbar` modifier and `.sheet` modifier to the `ScrollView` block, after the `.task` modifier (around line 31):

```swift
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showMaintenanceSheet = true
                } label: {
                    Label("Maintenance", systemImage: "wrench.and.screwdriver")
                }
            }
        }
        .sheet(isPresented: $showMaintenanceSheet) {
            MaintenanceWindowSheet(
                deviceName: device.name,
                apiService: viewModel.apiService,
                onDismiss: { showMaintenanceSheet = false }
            )
        }
```

Ensure `DeviceDetailViewModel` exposes `apiService`. Check if it already does:

```swift
// In DeviceDetailViewModel, apiService needs to be accessible.
// If it's private, change to:
let apiService: NetreoAPIService
```

- [ ] **Step 2: Build to verify compilation**

Run: `cd ios && xcodebuild -scheme BeNeM -destination 'platform=iOS,name=TomiPhone13' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Deploy to device and manually test**

Run: `cd ios && ./build_and_deploy.sh`

Verify:
1. Open any device detail view
2. Toolbar shows wrench icon
3. Tapping it opens the maintenance sheet
4. Duration chips work, Custom shows minutes field
5. Description is prefilled with "set by api_user on <current datetime>"
6. Create sends the request and shows success/error alert

- [ ] **Step 4: Commit**

```bash
git add ios/BeNeM/Views/DeviceDetailView.swift ios/BeNeM/ViewModels/DeviceDetailViewModel.swift
git commit -m "feat(ios): wire maintenance window sheet into device detail"
```

---

### Task 6: PWA — Maintenance API Function

**Files:**
- Create: `pwa/src/lib/api/maintenance.ts`

- [ ] **Step 1: Create the API function**

Create `pwa/src/lib/api/maintenance.ts`:

```typescript
import { postForm } from './client';
import { ApiException } from './types';
import type { BhnmConfig } from '../config';

export async function createMaintenanceWindow(
  config: BhnmConfig,
  deviceName: string,
  durationMinutes: number,
  comment: string,
): Promise<void> {
  const params: Record<string, string> = {
    password: config.apiKey,
    name: deviceName,
    duration: String(durationMinutes),
    comment,
  };
  if (config.pin) params.pin = config.pin;

  const raw = await postForm(
    config.baseUrl,
    '/api/proxy/maintenance/create',
    params,
    config.apiKey,
  );

  const record = raw as Record<string, unknown>;
  if (record.result === 'error') {
    const detail = typeof record.detail === 'string' ? record.detail : 'Failed to create maintenance window';
    throw new ApiException({ kind: 'server', status: 200, message: detail });
  }
}
```

- [ ] **Step 2: Verify TypeScript compilation**

Run: `cd pwa && npx tsc --noEmit`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add pwa/src/lib/api/maintenance.ts
git commit -m "feat(pwa): add createMaintenanceWindow API function"
```

---

### Task 7: PWA — Maintenance Dialog Component

**Files:**
- Create: `pwa/src/features/devices/MaintenanceDialog.tsx`

- [ ] **Step 1: Create the dialog component**

Create `pwa/src/features/devices/MaintenanceDialog.tsx`:

```tsx
import { useState } from 'react';

interface MaintenanceDialogProps {
  deviceName: string;
  isOpen: boolean;
  onClose: () => void;
  onSubmit: (durationMinutes: number, comment: string) => Promise<void>;
}

const DURATION_OPTIONS = [
  { label: '1h', minutes: 60 },
  { label: '6h', minutes: 360 },
  { label: '12h', minutes: 720 },
  { label: '24h', minutes: 1440 },
  { label: '7d', minutes: 10080 },
] as const;

function defaultComment(): string {
  const now = new Date();
  const pad = (n: number) => String(n).padStart(2, '0');
  const stamp = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())} ${pad(now.getHours())}:${pad(now.getMinutes())}`;
  return `set by api_user on ${stamp}`;
}

export function MaintenanceDialog({ deviceName, isOpen, onClose, onSubmit }: MaintenanceDialogProps) {
  const [selectedMinutes, setSelectedMinutes] = useState(60);
  const [isCustom, setIsCustom] = useState(false);
  const [customMinutes, setCustomMinutes] = useState('60');
  const [comment, setComment] = useState(defaultComment);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (!isOpen) return null;

  const durationMinutes = isCustom ? (parseInt(customMinutes, 10) || 0) : selectedMinutes;
  const isValid = durationMinutes >= 1;

  async function handleSubmit() {
    if (!isValid || isSubmitting) return;
    setIsSubmitting(true);
    setError(null);
    try {
      await onSubmit(durationMinutes, comment);
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not create maintenance window.');
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60" onClick={onClose}>
      <div
        className="bg-slate-900 rounded-lg p-6 w-full max-w-md mx-4 space-y-4"
        onClick={(e) => e.stopPropagation()}
      >
        <div>
          <h2 className="text-lg font-semibold text-white">Create Maintenance Window</h2>
          <p className="text-sm text-slate-400 mt-1">{deviceName}</p>
        </div>

        <div>
          <label className="text-xs text-slate-500 uppercase tracking-wide font-semibold">Duration</label>
          <div className="flex flex-wrap gap-2 mt-2">
            {DURATION_OPTIONS.map((opt) => (
              <button
                key={opt.label}
                className={`px-3 py-1.5 rounded text-sm font-semibold transition-colors ${
                  !isCustom && selectedMinutes === opt.minutes
                    ? 'bg-sky-600 text-white'
                    : 'bg-slate-800 text-slate-300 hover:bg-slate-700'
                }`}
                onClick={() => { setSelectedMinutes(opt.minutes); setIsCustom(false); }}
              >
                {opt.label}
              </button>
            ))}
            <button
              className={`px-3 py-1.5 rounded text-sm font-semibold transition-colors ${
                isCustom
                  ? 'bg-sky-600 text-white'
                  : 'bg-slate-800 text-slate-300 hover:bg-slate-700'
              }`}
              onClick={() => setIsCustom(true)}
            >
              Custom
            </button>
          </div>
          {isCustom && (
            <div className="mt-2 flex items-center gap-2">
              <input
                type="number"
                min="1"
                value={customMinutes}
                onChange={(e) => setCustomMinutes(e.target.value)}
                className="bg-slate-800 border border-slate-700 text-slate-200 rounded px-3 py-2 w-24 text-sm"
              />
              <span className="text-sm text-slate-400">minutes</span>
            </div>
          )}
        </div>

        <div>
          <label className="text-xs text-slate-500 uppercase tracking-wide font-semibold">Description</label>
          <input
            type="text"
            value={comment}
            onChange={(e) => setComment(e.target.value)}
            className="mt-2 w-full bg-slate-800 border border-slate-700 text-slate-200 rounded px-3 py-2 text-sm"
          />
        </div>

        {error && (
          <p className="text-sm text-red-400">{error}</p>
        )}

        <div className="flex gap-3 justify-end pt-2">
          <button
            onClick={onClose}
            className="px-4 py-2 rounded text-sm text-slate-400 border border-slate-700 hover:bg-slate-800"
            disabled={isSubmitting}
          >
            Cancel
          </button>
          <button
            onClick={handleSubmit}
            disabled={!isValid || isSubmitting}
            className="px-4 py-2 rounded text-sm font-semibold bg-sky-600 text-white hover:bg-sky-500 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {isSubmitting ? 'Creating...' : 'Create'}
          </button>
        </div>
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Verify TypeScript compilation**

Run: `cd pwa && npx tsc --noEmit`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add pwa/src/features/devices/MaintenanceDialog.tsx
git commit -m "feat(pwa): add MaintenanceDialog component"
```

---

### Task 8: PWA — Wire Dialog into DeviceDetailScreen

**Files:**
- Modify: `pwa/src/features/devices/DeviceDetailScreen.tsx`

- [ ] **Step 1: Add imports, state, and dialog to DeviceDetailScreen**

Add imports at the top of `DeviceDetailScreen.tsx`:

```typescript
import { useState } from 'react';
import { MaintenanceDialog } from './MaintenanceDialog';
import { createMaintenanceWindow } from '../../lib/api/maintenance';
import { useConfig } from '../../lib/config';
```

Inside the `DeviceDetailScreen` function, add state and config:

```typescript
  const config = useConfig();
  const [showMaintenance, setShowMaintenance] = useState(false);
```

Add the button after the Device Info Card `</div>` (after line 48), before the Current Issues section:

```tsx
          {/* Maintenance */}
          <button
            onClick={() => setShowMaintenance(true)}
            className="w-full bg-slate-900 rounded-lg p-3 text-sm font-semibold text-sky-400 hover:bg-slate-800 transition-colors"
          >
            Create Maintenance Window
          </button>

          <MaintenanceDialog
            deviceName={decodedName}
            isOpen={showMaintenance}
            onClose={() => setShowMaintenance(false)}
            onSubmit={(duration, comment) =>
              createMaintenanceWindow(config, decodedName, duration, comment)
            }
          />
```

- [ ] **Step 2: Verify TypeScript compilation**

Run: `cd pwa && npx tsc --noEmit`
Expected: No errors.

- [ ] **Step 3: Test in browser**

Run: `cd pwa && npm run dev`

Verify:
1. Open any device detail page
2. "Create Maintenance Window" button appears below device info
3. Clicking opens the dialog
4. Duration chips work, Custom shows minutes input
5. Description is prefilled
6. Cancel closes the dialog
7. Create sends the request (check network tab)

- [ ] **Step 4: Commit**

```bash
git add pwa/src/features/devices/DeviceDetailScreen.tsx
git commit -m "feat(pwa): wire maintenance dialog into device detail screen"
```

---

### Task 9: Deploy and End-to-End Test

- [ ] **Step 1: Deploy middleware**

```bash
cd middleware && ./deploy.sh
```

Verify health: `curl https://bhnm-apns.hurrikap.org/health`

- [ ] **Step 2: Deploy iOS to device**

```bash
cd ios && ./build_and_deploy.sh
```

- [ ] **Step 3: End-to-end test on iOS**

1. Open a device detail (e.g. raspi-050)
2. Tap the wrench icon
3. Select "1h" duration
4. Tap "Create"
5. Verify success alert
6. Verify on BHNM server: `mysql -e "SELECT * FROM devices.maintenance_window_log ORDER BY maintenance_window_log_id DESC LIMIT 1;"`

- [ ] **Step 4: End-to-end test on PWA**

1. Open a device detail in the PWA
2. Click "Create Maintenance Window"
3. Select a duration, click Create
4. Verify toast/dialog feedback
5. Verify in BHNM DB

- [ ] **Step 5: Final commit (if any adjustments)**

```bash
git add -A
git commit -m "fix: e2e adjustments for maintenance window"
```
