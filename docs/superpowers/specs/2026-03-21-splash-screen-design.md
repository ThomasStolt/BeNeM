# Splash Screen — Design Spec
**Date:** 2026-03-21
**Status:** Approved

## Overview

On app launch, a full-screen splash view overlays `ContentView`. It shows the `BMCHelixLogo` asset centered on a black background with a 3D glass effect and a one-shot shimmer animation. After ~1 second the splash fades out, revealing the already-loaded `ContentView` underneath.

## Visual Design

### Background
- Solid black, covering the full screen including safe areas (`.ignoresSafeArea()`)
- The system launch screen background (LaunchScreen.storyboard or Info.plist `UILaunchScreen`) must also be set to black to avoid a color flash before SwiftUI renders its first frame.

### Logo
- Asset: `BMCHelixLogo` (already in `Assets.xcassets`)
- Fixed width: **200 pt**, aspect ratio preserved (`.scaledToFit()`)
- Centered horizontally and vertically

### Glass / 3D Effect (applied to the logo image)
- **Shadow:** `shadow(color: .black.opacity(0.6), radius: 20, x: 0, y: 10)` — creates depth
- **Top-highlight overlay:** a vertical `LinearGradient` with stops `[(.white, 0.0), (.clear, 0.4)]` applied as a full-height overlay on top of the logo, opacity `0.25`. This produces a glassy highlight in the top 40% that fades to nothing.
- **Border:** a `RoundedRectangle(cornerRadius: 12)` stroke in `white.opacity(0.2)`, 1 pt line width, overlaid on the logo. The logo image itself is **not** clipped — the border is a visual hint only.
- Note: `BMCHelixLogo` is a 1x PNG asset; on 3x displays (e.g. iPhone 13) it will be upscaled by the system. This is acceptable for the initial implementation.

### Shimmer Animation
- A narrow white band (~30 pt wide) sweeps diagonally left-to-right across the logo.
- Implementation: a `Rectangle` of size `(width: 30, height: 400)` (fixed: 2× the 200 pt logo width, which safely covers the logo height regardless of aspect ratio) rotated `20°`, filled with a horizontal `LinearGradient` across its **own** narrow axis: `[.clear, .white.opacity(0.6), .clear]`. The gradient runs perpendicular to the sweep direction to create a soft-edged bright band.
- The band is offset along the x-axis, animating from `-200` to `+200` (matching the fixed 200 pt logo width).
- The entire shimmer is clipped to the logo's pixel shape using `.mask { Image("BMCHelixLogo").resizable().scaledToFit().frame(width: 200) }` — this prevents overflow into transparent PNG areas.
- Animation: one-shot, `.easeInOut(duration: 0.8)`, triggered at 0.1 s after appearance.

### Reduce Motion
- When `@Environment(\.accessibilityReduceMotion)` is `true`, both the shimmer and the fade-out animation are disabled. The splash appears instantly at full opacity and dismisses without animation at the 1.0 s mark.

## Timing

| Time | Event |
|------|-------|
| 0.0 s | App launches, `SplashView` visible at opacity 1.0 |
| 0.1 s | Shimmer animation starts (one-shot, 0.8 s) |
| 1.0 s | `withAnimation(.easeInOut(duration: 0.5)) { opacity = 0 }` starts |
| 1.5 s | `DispatchQueue.main.asyncAfter(deadline: .now() + 1.5)` calls `onDismiss()` → `showSplash = false` removes the overlay from the hierarchy |

The fade-out uses a fixed 1.5 s `asyncAfter` (not an animation completion handler) to keep the implementation simple. At 0.5 s duration the animation reliably completes well before 1.5 s under normal system load.

## Architecture

### New file: `BeNeM/Views/SplashView.swift`
```
struct SplashView: View {
    var onDismiss: () -> Void

    @State private var shimmerOffset: CGFloat = -200   // starts left of logo
    @State private var splashOpacity: Double = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    ...
}
```
- `onAppear` schedules:
  - `asyncAfter(0.1 s)` → trigger shimmer (skip if `reduceMotion`)
  - `asyncAfter(1.0 s)` → start opacity fade (skip animation if `reduceMotion`)
  - `asyncAfter(1.5 s)` → call `onDismiss()`

### Modified file: `BeNeM/BeNeMApp.swift`
- Add `@State private var showSplash = true` (valid on `App`-conforming structs in SwiftUI)
- `ContentView().overlay { if showSplash { SplashView { showSplash = false } } }`

## Constraints

- `ContentView` and all its ViewModels load in the background during the splash — no delay on first interaction
- No user interaction is possible while the splash is visible
- The splash runs exactly once per app launch (not on foreground returns)
- No new dependencies required
