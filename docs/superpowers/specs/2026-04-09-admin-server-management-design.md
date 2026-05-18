# Admin Server Management Design

**Date:** 2026-04-09
**Scope:** `middleware/benem-admin/`

## Summary

Add BHNM server list editing to the admin Settings page. Servers are currently
defined in `servers.json` and require CLI access to modify. This feature
provides a web UI for adding, editing, and deleting server entries, plus
passive and on-demand connection testing.

## Motivation

The user manages 3-4 BHNM servers per middleware instance. Changes are
infrequent but currently require SSH + manual JSON editing. A Settings-page
form makes this comfortable and less error-prone.

## Design

### UI: Inline Card List in Settings

A new "BHNM Servers" section is added to the Settings page, below the
existing TOTP and restart controls.

**Card layout (read-only state):**
- Server name (bold) + small status indicator (green/red dot from health check)
- Server ID (subdued)
- URL
- API Key (masked, last 4 chars visible)
- PIN ("none" if empty)
- Buttons: Edit, Test Connection, Delete

**Edit state:** Clicking "Edit" swaps the card to an inline form (HTMX) with
text inputs for all five fields. Save/Cancel buttons replace Edit/Delete.

**Add:** "+ Add Server" button at the bottom appends a blank editable card.
Cancel removes it. Save appends to `servers.json`.

**Delete:** Confirmation prompt, then removes the entry from `servers.json`
and the card from the DOM.

### Passive Health Check

On Settings page load, each server card includes an HTMX-triggered
`GET /admin/settings/server-health?id=<server_id>` that fires immediately.

- Makes a single lightweight BHNM API call (list devices with limit=1) using
  the server's URL, API key, and PIN.
- Returns: green dot (success) or red dot (failure) with error tooltip.
- Each card resolves independently; the page renders instantly.
- TLS verification respects `BHNM_TLS_VERIFY` env var.

### Detailed Connection Test

"Test Connection" button on each card runs the existing multi-step test
(DNS resolution, HTTPS reachability, API authentication) inline in the card.
Reuses `connection_test.py` logic with the specific server's credentials.

### Routes

New routes (all behind TOTP session auth + CSRF):

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/admin/settings/server-health` | Passive health check (per server) |
| POST | `/admin/settings/servers/add` | Add a new server entry |
| POST | `/admin/settings/servers/edit` | Update an existing server entry |
| POST | `/admin/settings/servers/delete` | Delete a server entry |
| POST | `/admin/settings/servers/test` | Run detailed connection test |
| GET | `/admin/settings/servers/edit-form` | Return editable card HTML (HTMX) |
| GET | `/admin/settings/servers/card` | Return read-only card HTML (HTMX) |

### Removals

- `GET /admin/test` page and `POST /admin/test` route
- Sidebar "Test" navigation link
- `GET /admin/reachability-check` endpoint (was used on QR generation page)
- Related template: `test.html`

### Data: servers.json

`servers.json` remains the single source of truth. Format unchanged:

```json
[
  {
    "id": "prod",
    "name": "Production",
    "url": "https://bhnm.corp.com",
    "api_key": "your-api-key-here",
    "pin": ""
  }
]
```

### Write Safety

- Atomic writes: write to temp file in same directory, then `os.rename()`.
- File-level locking (`fcntl.flock`) to prevent concurrent write corruption.
- Validation before write: `id` must be non-empty and unique, `name` and `url`
  required, `api_key` required, `pin` defaults to empty string.

### Docker Changes

- `docker-compose.yml`: change `servers.json` mount for `benem-admin` from
  `:ro` to read-write. The `bhnm-apns` container keeps `:ro`.
- No other infrastructure changes.

### Security

- All new routes require existing TOTP session authentication.
- CSRF middleware already covers all POST routes.
- API keys displayed masked in read-only view; full value shown only in edit form.
- No secrets logged; write operations logged to existing audit JSONL.
