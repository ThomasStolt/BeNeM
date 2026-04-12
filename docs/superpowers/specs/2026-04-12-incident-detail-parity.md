# Spec: Incident Detail iOS Parity + Duration Fix + Alarm Badge Fallback

**Date:** 2026-04-12  
**Status:** approved  
**Scope:** PWA `src/features/incidents/` + `src/lib/api/`

---

## Summary

Three related improvements to the PWA incident feature, all sharing a new `getIncidentDetail` API layer:

1. **Duration fix** — incident list rows currently always display "now"; fix `startTime` parsing so durations render correctly (`2h 18m`, `4d 7h`, etc.).
2. **Alarm badge fallback** — list rows show all-zero alarm badges when the middleware cache is cold; lazily fetch per-row counts from `getincidentdetail` when `alarmCounts` is null.
3. **Incident detail iOS parity** — rebuild `IncidentDetailScreen` to match the iOS app: Status section with alarm badges, full Incident Info card, Primary Alarms, Related Alarms, and Incident State Log (all loaded via `getincidentdetail`).

---

## 1. Duration Fix

### Root cause investigation

`parseRow` in `src/lib/api/incidents.ts` calls:

```ts
startTime: coerceStartTime(row.start_time ?? row.startTime)
```

`coerceStartTime` falls back to `new Date()` when the field is missing or unparseable, causing `formatDuration` to return `'now'` (diff < 1 min). During implementation, verify which field name the middleware cache and legacy BHNM endpoint actually use and fix the field lookup accordingly.

### Fix

- Identify the correct field name(s) from the API response (e.g. `open_time`, `incident_open_time`, `start_time`).
- Update `coerceStartTime` call in `parseRow` to cover the correct field name(s).
- `formatDuration` in `IncidentRow` already handles the full range (`now` / `Xm` / `Xh` / `Xd`) — no change needed there once `startTime` is correct.

---

## 2. New API Layer

### Types (`src/lib/api/types.ts`)

Add to the existing types file:

```ts
export interface IncidentAlarm {
  state: string;    // "CRITICAL", "MAJOR", "OK", etc.
  type: string;     // "Host", "Service", "Threshold"
  name: string;
  output: string;   // HTML-stripped
  time: Date | null;
}

export interface IncidentLogEntry {
  state: string;
  time: Date | null;
  username: string;
  comment: string;
}

export interface IncidentDetail {
  incidentId: string;
  title: string;
  deviceName: string;
  deviceIp: string | null;
  incidentState: string;
  alertType: string | null;
  openTime: Date | null;
  acknowledged: boolean;
  ackTime: Date | null;
  ackUser: string | null;
  ackComment: string | null;
  alarmCounts: AlarmCounts;         // computed from primary + related alarms
  primaryAlarms: IncidentAlarm[];
  relatedAlarms: IncidentAlarm[];
  incidentLog: IncidentLogEntry[];
}
```

### API function (`src/lib/api/incidents.ts`)

New export `getIncidentDetail(config: BhnmConfig, incidentId: string): Promise<IncidentDetail>`:

- Posts to `/api/incident_api.php` with `method=getincidentdetail` and `incident_id=<id>` — same transport pattern as `getIncidents`.
- Parses `json.incident` for top-level fields (title, deviceName, deviceIp, incidentState, alertType, openTime, acknowledged, ackTime, ackUser, ackComment).
- Parses `json.incident.detail.primary_alarm_log` → `primaryAlarms`.
- Parses `json.incident.detail.relatedalarms` → `relatedAlarms`.
- Parses `json.incident.detail.incident_log` → `incidentLog`.
- Strips HTML from `output` fields (`<br />` → `\n`, remaining tags removed).
- Computes `alarmCounts` by iterating all entries in `primaryAlarms + relatedAlarms` and mapping alarm `state` → color bucket (same mapping as iOS `fetchIncidentAlarmData`).
- Date strings parsed with ISO 8601; no-timezone strings treated as local time (matching iOS behaviour).

### Hook (`src/features/incidents/useIncidentDetail.ts`)

```ts
export function useIncidentDetail(incidentId: string) {
  const config = useConfig();
  return useQuery({
    queryKey: ['incidentDetail', incidentId],
    queryFn: () => getIncidentDetail(config, incidentId),
    staleTime: 60_000,
  });
}
```

---

## 3. Alarm Badge Fallback (List Rows)

### Behaviour

When `incident.alarmCounts` is `null` (middleware cache cold), `IncidentRow` triggers a `getincidentdetail` fetch for that incident and shows animated shimmer placeholders in place of the five alarm badge slots while loading. Once loaded, real counts replace the shimmers. React Query caches the result so subsequent renders (navigating back from detail) are instant.

### Implementation

In `IncidentRow`:

- If `incident.alarmCounts !== null`: render `<AlarmBadges>` as today.
- If `incident.alarmCounts === null`: call `useIncidentDetail(incident.incidentId)` with the result.
  - While loading: render five shimmer `<span>` elements (pulsing opacity via CSS animation).
  - On load: render `<AlarmBadges counts={detail.alarmCounts} />`.
  - On error: render `<AlarmBadges counts={EMPTY_COUNTS} />` (silent fallback, no UI error).

`IncidentRow` becomes a stateful component (hooks are fine in function components); no structural change to `SwipeableIncidentRow` or `IncidentListScreen`.

---

## 4. Incident Detail Screen Redesign

### Data sources

| Data | Source |
|---|---|
| `displayId`, `status`, `severity` | `useIncidents()` list cache (instant, no extra fetch) |
| All other fields | `useIncidentDetail(id)` — fetches on mount |

### Loading states

- List cache hit (instant): header renders immediately with displayId and ACK button.
- `useIncidentDetail` loading: show a skeleton for the Status section and cards below.
- `useIncidentDetail` error: show an error card with a retry button.

### Screen layout (top to bottom)

**Header bar** (sticky)
- Left: `← Back` link to `/incidents`
- Centre: "Incident Detail" (static title, not the incident ID)
- Right: subtle refresh indicator (spinning when `isFetching`)

**Status section** (card, always visible once detail loads)
- Left: ACK/UnACK icon button
  - Incident open/active → blue `✓` circle → tapping acknowledges
  - Acknowledged → blue `↩` circle → tapping unacknowledges
  - "ALARMS CLEARED" state → grey `✓` circle, non-interactive
  - While ACK call in-flight → spinner
- Centre: "Status" label + `StatusBadge` (OPEN / ACKD / CLRD)
- Right: `AlarmBadges` with counts from `IncidentDetail.alarmCounts`

**Incident Info card**
- Section header: "Incident Info"
- Rows (label / value): Incident ID · Title · Device · IP (omitted if blank) · Alert Type · Created · Duration · ACK Time (if acknowledged) · ACK User (if acknowledged, non-empty) · ACK Comment (if acknowledged, non-empty)
- Duration uses the same verbose format as iOS: `Xd Xh Xm Xs` (omitting leading zero units)
- Created uses existing `formatTimestamp` format

**Primary Alarms card** (omitted entirely when array is empty)
- Section header: "Primary Alarms (N)"
- Per alarm: state badge · type label · name (right-aligned) · output text · timestamp

**Related Alarms card** (omitted entirely when array is empty)
- Section header: "Related Alarms (N)"
- Same per-alarm layout as Primary Alarms

**Incident State Log card** (omitted entirely when array is empty)
- Section header: "Incident State Log"
- Per entry: state badge · timestamp (right-aligned) · username · comment (if non-empty)

### `StateBadge` component

New shared component `src/features/incidents/StateBadge.tsx` — maps a state string to a coloured pill. Used in alarm rows and log entries. Colour mapping:

| State(s) | Colour |
|---|---|
| CRITICAL, DOWN, OPEN | red |
| MAJOR, UNREACHABLE | orange |
| WARNING, MINOR | amber/dark-yellow |
| OK, RESOLVED, CLOSED, UP, NORMAL, RECOVERY, CLEARED, ALARMS CLEARED | green |
| ACKNOWLEDGED, ACK | blue |
| *(default)* | slate/grey |

Distinct from `StatusBadge` (which is specific to the three-state incident pill on list rows).

### ACK / UnACK flow

Unchanged from current implementation: optimistic UI via `queryClient.invalidateQueries`, toast feedback, `isAcking` spinner state. The ACK button moves from the header banner into the Status section card.

---

## 5. Files Affected

| File | Change |
|---|---|
| `src/lib/api/types.ts` | Add `IncidentAlarm`, `IncidentLogEntry`, `IncidentDetail` |
| `src/lib/api/incidents.ts` | Add `getIncidentDetail`, fix `startTime` field lookup in `parseRow` |
| `src/features/incidents/useIncidentDetail.ts` | New file — React Query hook |
| `src/features/incidents/StateBadge.tsx` | New file — state string → colour pill |
| `src/features/incidents/IncidentRow.tsx` | Add shimmer fallback when `alarmCounts` is null |
| `src/features/incidents/IncidentDetailScreen.tsx` | Full redesign per §4 |
| `src/features/incidents/__tests__/IncidentRow.test.tsx` | Add cold-cache shimmer test |
| `src/features/incidents/__tests__/IncidentDetailScreen.test.tsx` | Update for new layout |

---

## 6. Out of Scope

- No middleware changes required — `getincidentdetail` is called directly (same proxy transport as `getIncidents`).
- No changes to `SwipeableIncidentRow`, `AlarmBadges`, `StatusBadge`, or `SeverityBadge`.
- No Intersection Observer — React Query per-row is sufficient for typical incident counts.
