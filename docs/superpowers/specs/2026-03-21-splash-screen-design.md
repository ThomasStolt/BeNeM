# Splash Screen — Design Spec
**Date:** 2026-03-21
**Status:** Approved

## Overview

On app launch, a full-screen splash view overlays `ContentView`. It shows the `BMCHelixLogo` asset centered on a black background with a 3D glass effect and a one-shot shimmer animation. After ~1 second the splash fades out, revealing the already-loaded `ContentView` underneath.

## Visual Design

### Background
- Solid black, covering the full screen including safe areas (`.ignoresSafeArea()`)

### Logo
- Asset: `BMCHelixLogo` (already in `Assets.xcassets`)
- Width: 200 pt, aspect ratio preserved (`.scaledToFit()`)
- Centered horizontally and vertically

### Glass / 3D Effect (applied to the logo image)
- **Subtle shadow:** `shadow(color: .black.opacity(0.6), radius: 20, x: 0, y: 10)` — creates depth
- **Top-highlight overlay:** a white-to-transparent vertical linear gradient over the top ~40% of the logo, opacity ~0.25 — simulates a glass surface reflection
- **Border:** thin `RoundedRectangle` stroke in `white.opacity(0.2)` matching the logo's corner radius — gives a glass edge

### Shimmer Animation
- A narrow diagonal white band (~30 pt wide, full logo height, rotated ~20°) sweeps left-to-right across the logo
- Implemented via a masked `Rectangle` filled with a white gradient (`leading → clear → white → clear → trailing`)
- Offset animates from `-logoWidth` to `+logoWidth` once using `.easeInOut(duration: 0.8)`
- Clipped to the logo bounds so it doesn't overflow

## Timing

| Time | Event |
|------|-------|
| 0.0 s | App launches, `SplashView` is visible at opacity 1.0 |
| 0.1 s | Shimmer animation starts (one-shot, 0.8 s duration) |
| 1.0 s | Fade-out animation starts (`.easeInOut(duration: 0.5)`) |
| 1.5 s | `showSplash` set to `false` — overlay removed from hierarchy |

## Architecture

### New file: `BeNeM/Views/SplashView.swift`
- `struct SplashView: View`
- `@State private var shimmerOffset: CGFloat` — drives shimmer position
- `@State private var opacity: Double = 1.0` — drives fade-out
- `onAppear` triggers both animations via `DispatchQueue.main.asyncAfter`
- Accepts an `onDismiss: () -> Void` callback, called after the fade-out completes (at 1.5 s)

### Modified file: `BeNeM/BeNeMApp.swift`
- Add `@State private var showSplash = true`
- Wrap `ContentView()` with `.overlay { if showSplash { SplashView { showSplash = false } } }`

## Constraints

- `ContentView` and all its ViewModels load in the background during the splash — no delay on first interaction
- No user interaction is possible while the splash is visible (it covers everything)
- The splash runs exactly once per app launch (not on foreground returns)
- No new dependencies required
