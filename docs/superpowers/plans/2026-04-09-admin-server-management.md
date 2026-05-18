# Admin Server Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add BHNM server list editing (CRUD + health check + connection test) to the admin Settings page, replacing the standalone Connection Test page.

**Architecture:** Extend the existing `benem-admin` FastAPI app with new routes for server CRUD and health checks. The UI is added as a new section in `settings.html` using inline card layout with HTMX for interactivity. `servers.json` remains the single source of truth, made writable from the admin container.

**Tech Stack:** Python/FastAPI, Jinja2, HTMX, httpx (for health checks)

---

### Task 1: Make servers.json writable and add save/load helpers

**Files:**
- Modify: `middleware/docker-compose.yml:20` (change `:ro` to writable)
- Modify: `middleware/benem-admin/servers.py`

- [ ] **Step 1: Update docker-compose.yml**

Change the `benem-admin` servers.json mount from read-only to writable:

```yaml
# In benem-admin service volumes, change:
      - ./servers.json:/app/servers.json:ro
# To:
      - ./servers.json:/app/servers.json
```

The `bhnm-apns` service keeps its `:ro` mount — it only reads.

- [ ] **Step 2: Add save_servers() to servers.py**

Add an atomic write function with file locking to `middleware/benem-admin/servers.py`:

```python
import fcntl
import tempfile


def save_servers(servers: list[Server]) -> None:
    """Atomically write servers list to servers.json with file locking."""
    path = os.environ.get("SERVERS_JSON_PATH", "/app/servers.json")
    data = [
        {"id": s.id, "name": s.name, "url": s.url, "api_key": s.api_key, "pin": s.pin}
        for s in servers
    ]
    dir_path = os.path.dirname(path) or "."
    fd = os.open(path, os.O_RDWR | os.O_CREAT)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        with tempfile.NamedTemporaryFile(
            mode="w", dir=dir_path, suffix=".tmp", delete=False
        ) as tmp:
            json.dump(data, tmp, indent=2)
            tmp.write("\n")
            tmp_path = tmp.name
        os.rename(tmp_path, path)
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)
```

- [ ] **Step 3: Commit**

```bash
git add middleware/docker-compose.yml middleware/benem-admin/servers.py
git commit -m "feat(admin): make servers.json writable, add save_servers()"
```

---

### Task 2: Add server CRUD routes

**Files:**
- Modify: `middleware/benem-admin/main.py`

- [ ] **Step 1: Add imports**

At the top of `main.py`, add `save_servers` to the servers import:

```python
from servers import load_servers, get_server, save_servers, Server
```

- [ ] **Step 2: Update settings_page to pass servers list**

Replace the existing `settings_page` route (line 421-430) to include servers:

```python
@app.get("/admin/settings", response_class=HTMLResponse)
def settings_page(request: Request):
    if not auth.is_authenticated(request):
        return auth.redirect_to_login()
    try:
        servers = load_servers()
    except FileNotFoundError:
        servers = []
    return templates.TemplateResponse(request, "settings.html", {
        "active": "settings",
        "totp_qr_b64": _totp_qr_b64(),
        "version": VERSION,
        "can_restart": _can_restart(),
        "restart_initiated": False,
        "servers": servers,
    })
```

- [ ] **Step 3: Add server card HTMX fragment routes**

Add these routes after the `settings_page` route in `main.py`:

```python
# ── Server Management (HTMX fragments) ────────────────────────────────────

@app.get("/admin/settings/servers/card", response_class=HTMLResponse)
def server_card_readonly(request: Request, server_id: str = ""):
    """Return a read-only server card fragment (HTMX)."""
    if not auth.is_authenticated(request):
        return HTMLResponse("", status_code=401)
    server = get_server(server_id)
    if not server:
        return HTMLResponse("", status_code=404)
    return templates.TemplateResponse(request, "_server_card.html", {
        "s": server,
    })


@app.get("/admin/settings/servers/edit-form", response_class=HTMLResponse)
def server_edit_form(request: Request, server_id: str = ""):
    """Return an editable server card fragment (HTMX). Empty server_id = new server."""
    if not auth.is_authenticated(request):
        return HTMLResponse("", status_code=401)
    if server_id:
        server = get_server(server_id)
        if not server:
            return HTMLResponse("", status_code=404)
    else:
        server = Server(id="", name="", url="", api_key="", pin="")
    return templates.TemplateResponse(request, "_server_form.html", {
        "s": server,
        "is_new": not server_id,
    })


@app.post("/admin/settings/servers/add", response_class=HTMLResponse)
def server_add(
    request: Request,
    id: str = Form(...),
    name: str = Form(...),
    url: str = Form(...),
    api_key: str = Form(...),
    pin: str = Form(""),
):
    if not auth.is_authenticated(request):
        return HTMLResponse("", status_code=401)
    id = id.strip()
    name = name.strip()
    url = url.strip().rstrip("/")
    api_key = api_key.strip()
    pin = pin.strip()
    if not id or not name or not url or not api_key:
        return HTMLResponse(
            '<div class="alert alert-red">All fields except PIN are required.</div>',
            status_code=422,
        )
    try:
        servers = load_servers()
    except FileNotFoundError:
        servers = []
    if any(s.id == id for s in servers):
        return HTMLResponse(
            f'<div class="alert alert-red">Server ID "{escape(id)}" already exists.</div>',
            status_code=422,
        )
    new_server = Server(id=id, name=name, url=url, api_key=api_key, pin=pin)
    servers.append(new_server)
    save_servers(servers)
    return templates.TemplateResponse(request, "_server_card.html", {
        "s": new_server,
    })


@app.post("/admin/settings/servers/edit", response_class=HTMLResponse)
def server_edit(
    request: Request,
    original_id: str = Form(...),
    id: str = Form(...),
    name: str = Form(...),
    url: str = Form(...),
    api_key: str = Form(...),
    pin: str = Form(""),
):
    if not auth.is_authenticated(request):
        return HTMLResponse("", status_code=401)
    id = id.strip()
    name = name.strip()
    url = url.strip().rstrip("/")
    api_key = api_key.strip()
    pin = pin.strip()
    if not id or not name or not url or not api_key:
        return HTMLResponse(
            '<div class="alert alert-red">All fields except PIN are required.</div>',
            status_code=422,
        )
    try:
        servers = load_servers()
    except FileNotFoundError:
        servers = []
    # Check for ID collision (if ID changed)
    if id != original_id and any(s.id == id for s in servers):
        return HTMLResponse(
            f'<div class="alert alert-red">Server ID "{escape(id)}" already exists.</div>',
            status_code=422,
        )
    idx = next((i for i, s in enumerate(servers) if s.id == original_id), None)
    if idx is None:
        return HTMLResponse(
            '<div class="alert alert-red">Server not found.</div>',
            status_code=404,
        )
    servers[idx] = Server(id=id, name=name, url=url, api_key=api_key, pin=pin)
    save_servers(servers)
    return templates.TemplateResponse(request, "_server_card.html", {
        "s": servers[idx],
    })


@app.post("/admin/settings/servers/delete", response_class=HTMLResponse)
def server_delete(request: Request, server_id: str = Form(...)):
    if not auth.is_authenticated(request):
        return HTMLResponse("", status_code=401)
    try:
        servers = load_servers()
    except FileNotFoundError:
        return HTMLResponse("")
    servers = [s for s in servers if s.id != server_id]
    save_servers(servers)
    return HTMLResponse("")  # HTMX removes the card from DOM
```

- [ ] **Step 4: Commit**

```bash
git add middleware/benem-admin/main.py
git commit -m "feat(admin): add server CRUD routes"
```

---

### Task 3: Add server health check route

**Files:**
- Modify: `middleware/benem-admin/main.py`

- [ ] **Step 1: Add the health check endpoint**

Add this route alongside the other server management routes in `main.py`:

```python
@app.get("/admin/settings/server-health", response_class=HTMLResponse)
async def server_health(request: Request, id: str = ""):
    """Passive health check — one lightweight BHNM API call per server."""
    if not auth.is_authenticated(request):
        return HTMLResponse("", status_code=401)
    server = get_server(id)
    if not server:
        return HTMLResponse(
            '<span class="health-dot health-unknown" title="Server not found"></span>'
        )
    tls_verify = os.environ.get("BHNM_TLS_VERIFY", "true").lower() != "false"
    try:
        form: dict = {"password": server.api_key, "method": "getdevices", "max": "1"}
        if server.pin:
            form["pin"] = server.pin
        async with httpx.AsyncClient(timeout=5.0, verify=tls_verify) as client:
            resp = await client.post(
                f"{server.url.rstrip('/')}/api/incident_api.php", data=form
            )
        if resp.status_code == 200:
            return HTMLResponse(
                '<span class="health-dot health-ok" title="Connected"></span>'
            )
        else:
            return HTMLResponse(
                f'<span class="health-dot health-fail" title="HTTP {resp.status_code}"></span>'
            )
    except Exception as e:
        detail = str(e)[:80]
        return HTMLResponse(
            f'<span class="health-dot health-fail" title="{escape(detail)}"></span>'
        )
```

- [ ] **Step 2: Add the detailed test route**

Add a route that runs the full multi-step connection test inline in a card:

```python
@app.post("/admin/settings/servers/test", response_class=HTMLResponse)
def server_test(request: Request, server_id: str = Form(...)):
    """Run detailed connection test (DNS → HTTPS → API auth) for a server."""
    if not auth.is_authenticated(request):
        return HTMLResponse("", status_code=401)
    server = get_server(server_id)
    if not server:
        return HTMLResponse('<div class="alert alert-red">Server not found.</div>')
    results = run_test(server.url, server.api_key, server.pin)
    return templates.TemplateResponse(request, "_server_test_results.html", {
        "results": results,
    })
```

- [ ] **Step 3: Commit**

```bash
git add middleware/benem-admin/main.py
git commit -m "feat(admin): add server health check and detailed test routes"
```

---

### Task 4: Create HTMX template fragments

**Files:**
- Create: `middleware/benem-admin/templates/_server_card.html`
- Create: `middleware/benem-admin/templates/_server_form.html`
- Create: `middleware/benem-admin/templates/_server_test_results.html`

- [ ] **Step 1: Create the read-only server card fragment**

Create `middleware/benem-admin/templates/_server_card.html`:

```html
<div class="card server-card" id="server-{{ s.id }}">
  <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:12px;">
    <div style="display:flex;align-items:center;gap:8px;">
      <strong style="color:var(--accent);">{{ s.name }}</strong>
      <span hx-get="/admin/settings/server-health?id={{ s.id }}"
            hx-trigger="load"
            hx-swap="innerHTML">
        <span class="health-dot health-loading" title="Checking..."></span>
      </span>
    </div>
    <span style="font-size:11px;color:var(--text-dim);">id: {{ s.id }}</span>
  </div>
  <dl class="info" style="margin-bottom:14px;">
    <div>
      <dt>URL</dt>
      <dd>{{ s.url }}</dd>
    </div>
    <div>
      <dt>API Key</dt>
      <dd>{{ '••••••••' + s.api_key[-4:] if s.api_key|length > 4 else '••••' }}</dd>
    </div>
    <div>
      <dt>PIN</dt>
      <dd>{{ s.pin if s.pin else '(none)' }}</dd>
    </div>
  </dl>
  <div id="test-results-{{ s.id }}"></div>
  <div style="display:flex;gap:8px;flex-wrap:wrap;">
    <button class="btn btn-ghost btn-sm"
            hx-get="/admin/settings/servers/edit-form?server_id={{ s.id }}"
            hx-target="#server-{{ s.id }}"
            hx-swap="outerHTML">Edit</button>
    <button class="btn btn-ghost btn-sm" style="color:var(--green);border-color:rgba(34,217,138,0.35);"
            hx-post="/admin/settings/servers/test"
            hx-vals='{"server_id": "{{ s.id }}"}'
            hx-target="#test-results-{{ s.id }}"
            hx-swap="innerHTML"
            hx-indicator="#test-spin-{{ s.id }}">
      Test Connection
      <span id="test-spin-{{ s.id }}" class="htmx-indicator" style="font-size:11px;">...</span>
    </button>
    <button class="btn btn-danger btn-sm"
            hx-post="/admin/settings/servers/delete"
            hx-vals='{"server_id": "{{ s.id }}"}'
            hx-target="#server-{{ s.id }}"
            hx-swap="outerHTML"
            hx-confirm="Delete server '{{ s.name }}'? This cannot be undone.">Delete</button>
  </div>
</div>
```

- [ ] **Step 2: Create the editable server form fragment**

Create `middleware/benem-admin/templates/_server_form.html`:

```html
<div class="card server-card" id="server-{{ s.id or 'new' }}">
  <h2>{{ 'New Server' if is_new else 'Edit: ' + s.name }}</h2>
  <form hx-post="/admin/settings/servers/{{ 'add' if is_new else 'edit' }}"
        hx-target="#server-{{ s.id or 'new' }}"
        hx-swap="outerHTML">
    {% if not is_new %}
    <input type="hidden" name="original_id" value="{{ s.id }}">
    {% endif %}
    <div class="form-group">
      <label>Server ID</label>
      <input type="text" name="id" value="{{ s.id }}" placeholder="e.g. prod"
             class="mono" required>
    </div>
    <div class="form-group">
      <label>Display Name</label>
      <input type="text" name="name" value="{{ s.name }}" placeholder="e.g. Production" required>
    </div>
    <div class="form-group">
      <label>BHNM URL</label>
      <input type="text" name="url" value="{{ s.url }}" placeholder="https://bhnm.example.com"
             class="mono" required>
    </div>
    <div class="form-group">
      <label>API Key</label>
      <input type="password" name="api_key" value="{{ s.api_key }}" placeholder="API key" required>
    </div>
    <div class="form-group">
      <label>PIN <span style="color:var(--text-dim);font-weight:400;">(SaaS only, leave empty for on-prem)</span></label>
      <input type="text" name="pin" value="{{ s.pin }}" placeholder="(empty)" class="mono">
    </div>
    <div style="display:flex;gap:8px;">
      <button type="submit" class="btn btn-primary btn-sm">Save</button>
      {% if is_new %}
      <button type="button" class="btn btn-ghost btn-sm"
              onclick="this.closest('.server-card').remove()">Cancel</button>
      {% else %}
      <button type="button" class="btn btn-ghost btn-sm"
              hx-get="/admin/settings/servers/card?server_id={{ s.id }}"
              hx-target="#server-{{ s.id }}"
              hx-swap="outerHTML">Cancel</button>
      {% endif %}
    </div>
  </form>
</div>
```

- [ ] **Step 3: Create the test results fragment**

Create `middleware/benem-admin/templates/_server_test_results.html`:

```html
<div style="margin-bottom:10px;margin-top:10px;">
  {% for r in results %}
  <div class="result-item">
    <div class="result-icon {{ 'ok' if r.ok else 'fail' }}">
      {{ '✓' if r.ok else '✗' }}
    </div>
    <div>
      <div class="result-step">{{ r.step }}</div>
      <div class="result-detail">{{ r.detail }}</div>
    </div>
  </div>
  {% endfor %}
</div>
```

- [ ] **Step 4: Commit**

```bash
git add middleware/benem-admin/templates/_server_card.html \
        middleware/benem-admin/templates/_server_form.html \
        middleware/benem-admin/templates/_server_test_results.html
git commit -m "feat(admin): add server card HTMX template fragments"
```

---

### Task 5: Update settings.html with server management section

**Files:**
- Modify: `middleware/benem-admin/templates/settings.html`

- [ ] **Step 1: Add the BHNM Servers section and health-dot CSS**

Replace the full content of `settings.html` with:

```html
{% extends "base.html" %}
{% block content %}
<style>
  .health-dot {
    display: inline-block;
    width: 8px;
    height: 8px;
    border-radius: 50%;
    vertical-align: middle;
  }
  .health-ok {
    background: var(--green);
    box-shadow: 0 0 6px var(--green);
  }
  .health-fail {
    background: var(--red);
    box-shadow: 0 0 6px var(--red);
  }
  .health-unknown {
    background: var(--text-dim);
  }
  .health-loading {
    background: var(--text-dim);
    animation: dot-pulse 1.5s ease-in-out infinite;
  }
</style>

<h1>Settings</h1>

<div style="max-width: 520px;">

  <div class="card">
    <h2>BHNM Servers</h2>
    <p style="font-size:13px;color:var(--text-muted);margin-bottom:16px;">
      Manage the BHNM server connections used for link generation and API proxy.
    </p>
    <div id="server-list">
      {% for s in servers %}
      {% include "_server_card.html" %}
      {% endfor %}
    </div>
    <button class="btn btn-ghost btn-sm" style="width:100%;margin-top:4px;"
            hx-get="/admin/settings/servers/edit-form"
            hx-target="#server-list"
            hx-swap="beforeend">+ Add Server</button>
  </div>

  <div class="card">
    <h2>Authenticator Setup</h2>
    <p style="font-size:13px;color:var(--text-muted);margin-bottom:16px;">
      Scan this QR code in Google Authenticator, 1Password, or Authy.
      The TOTP secret is read from <code class="pill">TOTP_SECRET</code>
      in your <code class="pill">.env</code> file.
    </p>
    {% if totp_qr_b64 %}
    <div style="display:flex;justify-content:center;margin-bottom:14px;">
      <img src="data:image/png;base64,{{ totp_qr_b64 }}"
           alt="TOTP QR Code"
           style="width:180px;height:180px;border:1px solid var(--border);border-radius:8px;background:#fff;padding:8px;">
    </div>
    {% else %}
    <div class="alert alert-amber">
      TOTP_SECRET is not configured. Set it in .env and restart.
    </div>
    {% endif %}
    <p style="font-size:11px;color:var(--text-dim);text-align:center;">
      To rotate: edit <code class="pill">.env</code>, set a new
      <code class="pill">TOTP_SECRET</code>, restart the container, then re-scan.
    </p>
  </div>

  <div class="card">
    <h2>App Info</h2>
    <dl class="info">
      <div>
        <dt>Version</dt>
        <dd>{{ version }}</dd>
      </div>
    </dl>
  </div>

  <div class="card">
    <h2>Container</h2>
    {% if can_restart %}
    <p style="font-size:13px;color:var(--text-muted);margin-bottom:14px;">
      Restart the <code class="pill">benem-admin</code> container.
    </p>
    <form method="post" action="/admin/restart"
          onsubmit="return confirm('Restart container? You will be disconnected briefly.')">
      <button type="submit" class="btn btn-danger btn-sm">
        Restart Container
      </button>
    </form>
    {% else %}
    <p style="font-size:13px;color:var(--text-muted);">
      Restart manually via SSH:
      <code class="pill">docker restart benem-admin</code>
    </p>
    {% endif %}
    {% if restart_initiated %}
    <div class="alert alert-green" style="margin-top:14px;margin-bottom:0;">
      Restart initiated. Reconnect in a few seconds.
    </div>
    {% endif %}
  </div>

</div>
{% endblock %}
```

- [ ] **Step 2: Commit**

```bash
git add middleware/benem-admin/templates/settings.html
git commit -m "feat(admin): add BHNM Servers section to settings page"
```

---

### Task 6: Remove Connection Test page and reachability check

**Files:**
- Modify: `middleware/benem-admin/main.py` (remove routes)
- Modify: `middleware/benem-admin/templates/base.html` (remove sidebar link)
- Delete: `middleware/benem-admin/templates/test.html`

- [ ] **Step 1: Remove routes from main.py**

Remove these three route functions from `main.py`:
1. The `test_page` route (`GET /admin/test`) — lines 292-305
2. The `test_submit` route (`POST /admin/test`) — lines 308-323
3. The `reachability_check` route (`GET /admin/reachability-check`) — lines 200-232

Also remove the `testReachability` JS function call and the `bhnm-test-result` div references from `server_url_fragment` route (lines 179-197). Replace it with a simpler version:

```python
@app.get("/admin/server-url", response_class=HTMLResponse)
def server_url_fragment(request: Request, server_id: str = ""):
    """HTMX endpoint — returns updated URL field HTML for the selected server."""
    if not auth.is_authenticated(request):
        return HTMLResponse("", status_code=401)
    server = get_server(server_id)
    if not server:
        return HTMLResponse(
            '<input type="text" value="" readonly class="flex-1">'
        )
    url_attr = escape(server.url, quote=True)
    return HTMLResponse(
        f'<input type="text" value="{url_attr}" readonly class="flex-1">'
    )
```

- [ ] **Step 2: Remove sidebar link from base.html**

In `middleware/benem-admin/templates/base.html`, remove the Connection Test sidebar link (lines 570-572):

```html
      <!-- DELETE these lines: -->
      <a href="/admin/test"
         class="{{ 'active' if active == 'test' else '' }}">
        Connection Test
      </a>
```

- [ ] **Step 3: Remove the reachability test button and JS from generate.html**

In `middleware/benem-admin/templates/generate.html`:
- Remove the `testReachability` button from the server URL row (around line 318-324)
- Remove the `<div id="bhnm-test-result"></div>` element (line 324)
- Remove the second test button instance (around line 332-335)
- Remove the `testReachability()` JavaScript function (lines 608-624)

- [ ] **Step 4: Delete test.html**

```bash
rm middleware/benem-admin/templates/test.html
```

- [ ] **Step 5: Commit**

```bash
git add middleware/benem-admin/main.py \
        middleware/benem-admin/templates/base.html \
        middleware/benem-admin/templates/generate.html
git rm middleware/benem-admin/templates/test.html
git commit -m "refactor(admin): remove standalone Connection Test page, consolidate into Settings"
```

---

### Task 7: Bump version and final verification

**Files:**
- Modify: `middleware/benem-admin/main.py:1` (version bump)

- [ ] **Step 1: Bump the admin version**

Change line 1 of `main.py`:

```python
VERSION = "1.5.0"
```

- [ ] **Step 2: Verify the full flow locally**

Build and test:

```bash
cd middleware
docker compose build benem-admin
docker compose up -d benem-admin
```

Manual verification checklist:
1. Open `/admin/settings` — server cards render with green/red health dots
2. Click "Edit" on a server — form appears inline, Cancel returns to read-only
3. Change a field and Save — card updates, `servers.json` reflects the change
4. Click "+ Add Server" — blank form appears, fill in and Save
5. Click "Delete" — confirmation, then card removed
6. Click "Test Connection" — DNS/HTTPS/API results appear inline
7. Sidebar no longer shows "Connection Test" link
8. Generate page no longer has reachability test buttons
9. Existing functionality (link generation, push, log) still works

- [ ] **Step 3: Commit**

```bash
git add middleware/benem-admin/main.py
git commit -m "chore(admin): bump version to 1.5.0"
```
