# Device Detail Header — 3-Column Layout with Latency Histogram

**Date:** 2026-04-03
**Status:** Approved
**Scope:** Layout experiment — rollback if too cramped on device

## Summary

Redesign the DeviceDetailView header card from 2 columns (icon | info) to 3 columns (icon | info | latency histogram). The latency histogram provides an at-a-glance 24-hour trend directly in the header.

## Layout

| Column | Width | Content |
|--------|-------|---------|
| Left | ~60pt fixed | `DeviceTypeIcon` (reduced from 90pt to ~56pt) |
| Middle | flex | Device name, IP, category, site (MarqueeText, same as today) |
| Right | ~100pt fixed | Mini bar histogram — bars only, no labels or numbers |

- Icon shrinks from 90pt to ~56pt to make room
- Middle column uses flexible width with `min-width: 0` behavior so MarqueeText still scrolls for long names
- Right column is fixed width, flex-shrink 0

## Histogram Specification

- **Data source:** Reuse existing `latencyStates` from `DeviceDetailViewModel` — no new API calls
- **Time frame:** "Last 24 Hours" (changed from current "Last Hour" default)
- **Downsampling:** Reduce 24h data points to ~14-20 bars using existing `downsample()` function
- **Bar color:** Single uniform green — `Color(red: 0.2, green: 0.8, blue: 0.4)`
- **Bar shape:** Rounded top corners, anchored to bottom
- **Rendering:** SwiftUI Charts `BarMark` or simple `HStack` of `RoundedRectangle`s
- **No text:** No value labels, no axis labels, no "Latency" title — bars only
- **Empty state:** If latency data hasn't loaded or is unavailable, the right column shows nothing — header renders as a natural 2-column layout until data arrives

## Changed Files

### DeviceDetailView.swift
- `headerSection()` — change from 2-column `HStack` to 3-column
  - Left: `DeviceTypeIcon` with size reduced to 56
  - Middle: existing `VStack` of MarqueeText fields (name, IP, category, site)
  - Right: new private subview for mini bar histogram
- Add private mini histogram subview that takes `[MetricDataPoint]` and renders bars

### DeviceDetailViewModel.swift
- Change latency time frame from `"Last Hour"` to `"Last 24 Hours"`

### Not Changed
- Full latency section below header — stays as-is (now shows 24h data as side effect)
- No new files, models, or API calls
- `MarqueeText`, `DeviceTypeIcon` — untouched
