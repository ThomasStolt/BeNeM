# Design: Maintenance Window – iOS parity

**Date:** 2026-04-11
**Status:** approved
**Scope:** `ios/BeNeM/Views/MaintenanceWindowSheet.swift` + `shared/feature-spec.md`

---

## Background

The PWA shipped the maintenance window feature (`shipped-pwa`). The iOS app already has
the skeleton in place — `MaintenanceWindowSheet.swift`, `NetreoAPIService.createMaintenanceWindow()`,
and the wrench toolbar button in `DeviceDetailView`. What's missing is parity with the spec
in three areas: correct prefix content, non-editable prefix UI, and the 255-char limit with
counter.

## What changes

All changes are confined to `MaintenanceWindowSheet.swift`. No other files need touching.

### 1. Prefix — content

**Current:** `"set by api_user on YYYY-MM-DD HH:mm"` (hardcoded)

**Target:** `"Created by <ackUser> on YYYY-MM-DD HH:MM: "`

- `<ackUser>` is read from `@AppStorage("netreo_ack_user")` — same key used in
  `IncidentListView`, `IncidentDetailView`, etc. Falls back to `"unknown"` if blank.
- Timestamp is local wall-clock at the moment the sheet opens (not at submit), formatted
  `YYYY-MM-DD HH:MM` (zero-padded, 24-hour).
- The trailing `": "` (colon + space) is part of the prefix so the optional user note
  reads naturally after it.

The prefix is captured once at init time as a `let` constant and does not change while
the sheet is open.

### 2. Prefix — non-editable UI (Option A layout)

The `Section("Description")` becomes:

```
Section("Description") {
    Text(prefix)                             // grey, footnote, non-interactive
        .font(.footnote)
        .foregroundColor(.secondary)
    TextField("optional note…", text: $userNote)
} footer: {
    Text("\(remaining) left")
        .foregroundColor(remaining <= 20 ? .yellow : .secondary)
}
```

The state variable is renamed from `comment` to `userNote` (stores only the user-typed
portion). The value sent to the API is `prefix + userNote`.

### 3. 255-char limit + counter

- `remaining` computed property: `max(0, 255 - prefix.count - userNote.count)`
- `.onChange(of: userNote)` clamps to `String(userNote.prefix(255 - prefix.count))`
- Section footer shows `"\(remaining) left"` in `.secondary`; turns `.yellow` when ≤ 20

## What does NOT change

- `NetreoAPIService.createMaintenanceWindow()` — already correct; already sends `prefix + userNote`
  (once we build the full comment string before calling it)
- `DeviceDetailView` — wrench button and sheet presentation already in place
- API endpoint, middleware contract, duration picker, custom duration field — all unchanged

## Post-implementation

Update `shared/feature-spec.md` Maintenance Windows status line from `shipped-pwa` to
`shipped-both`.
