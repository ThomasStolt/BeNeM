# Splash Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a full-screen black splash view with a glass-effect BMCHelixLogo and shimmer animation that fades out after 1 second on every app launch.

**Architecture:** `SplashView` is overlaid on top of `ContentView` in `BeNeMApp`. `ContentView` loads in the background while the splash is visible. After 1 s the splash fades out; after 1.5 s it is removed from the hierarchy. The `Info.plist` launch screen background is set to black to prevent a color flash before SwiftUI renders its first frame.

**Tech Stack:** SwiftUI, `DispatchQueue.main.asyncAfter`, `withAnimation`, `@Environment(\.accessibilityReduceMotion)`, Assets.xcassets color set.

---

### Task 1: Set launch screen background to black

**Files:**
- Modify: `BeNeM/Info.plist` (UILaunchScreen dict)
- Modify: `BeNeM/Assets.xcassets` (add `SplashBackground` color set)

**Why:** iOS shows the system launch screen before SwiftUI renders its first frame. Without a matching black background, there is a visible white flash before `SplashView` appears.

- [ ] **Step 1: Add a black color asset**

  Create `BeNeM/Assets.xcassets/SplashBackground.colorset/Contents.json` with the following content:

  ```json
  {
    "colors" : [
      {
        "color" : {
          "color-space" : "srgb",
          "components" : {
            "alpha" : "1.000",
            "blue" : "0.000",
            "green" : "0.000",
            "red" : "0.000"
          }
        },
        "idiom" : "universal"
      }
    ],
    "info" : {
      "author" : "xcode",
      "version" : 1
    }
  }
  ```

- [ ] **Step 2: Reference the color in Info.plist**

  In `BeNeM/Info.plist`, replace the empty `UILaunchScreen` dict:
  ```xml
  <key>UILaunchScreen</key>
  <dict/>
  ```
  with:
  ```xml
  <key>UILaunchScreen</key>
  <dict>
      <key>UIColorName</key>
      <string>SplashBackground</string>
  </dict>
  ```

- [ ] **Step 3: Build and verify**

  Run: `./build_and_deploy.sh`

  Expected: Build succeeds. On device, cold launch shows a black background before the app UI appears (no white flash).

- [ ] **Step 4: Commit**

  ```bash
  git add BeNeM/Assets.xcassets/SplashBackground.colorset/Contents.json BeNeM/Info.plist
  git commit -m "feat: set launch screen background to black for splash screen"
  ```

---

### Task 2: Create SplashView

**Files:**
- Create: `BeNeM/Views/SplashView.swift`

**What this file does:** Full-screen black overlay with the `BMCHelixLogo` centered, glass effect (shadow + top-highlight overlay + border), one-shot shimmer animation, and opacity-based fade-out. Calls `onDismiss()` after 1.5 s so the caller can remove it from the view hierarchy.

- [ ] **Step 1: Create `BeNeM/Views/SplashView.swift`**

  ```swift
  import SwiftUI

  struct SplashView: View {
      var onDismiss: () -> Void

      @State private var shimmerOffset: CGFloat = -200
      @State private var splashOpacity: Double = 1.0
      @Environment(\.accessibilityReduceMotion) private var reduceMotion

      var body: some View {
          ZStack {
              Color.black.ignoresSafeArea()

              logoWithEffects
                  .frame(width: 200)
          }
          .opacity(splashOpacity)
          .onAppear(perform: startAnimations)
      }

      // MARK: - Logo

      private var logoWithEffects: some View {
          Image("BMCHelixLogo")
              .resizable()
              .scaledToFit()
              // Glass: depth shadow
              .shadow(color: .black.opacity(0.6), radius: 20, x: 0, y: 10)
              // Glass: top highlight
              .overlay(topHighlight)
              // Glass: border
              .overlay(glassBorder)
              // Shimmer clipped to logo pixels
              .overlay(shimmerBand.mask(logoMask))
      }

      private var topHighlight: some View {
          LinearGradient(
              stops: [
                  .init(color: .white, location: 0.0),
                  .init(color: .clear, location: 0.4)
              ],
              startPoint: .top,
              endPoint: .bottom
          )
          .opacity(0.25)
      }

      private var glassBorder: some View {
          RoundedRectangle(cornerRadius: 12)
              .stroke(Color.white.opacity(0.2), lineWidth: 1)
      }

      // MARK: - Shimmer

      private var shimmerBand: some View {
          Rectangle()
              .fill(
                  LinearGradient(
                      stops: [
                          .init(color: .clear, location: 0.0),
                          .init(color: .white.opacity(0.6), location: 0.5),
                          .init(color: .clear, location: 1.0)
                      ],
                      startPoint: .leading,
                      endPoint: .trailing
                  )
              )
              .frame(width: 30, height: 400)
              .rotationEffect(.degrees(20))
              .offset(x: shimmerOffset)
      }

      // Note: BMCHelixLogo.png is an indexed-color PNG with a tRNS transparency chunk,
      // so SwiftUI correctly renders it with transparent areas. The mask below clips
      // the shimmer to the logo's opaque pixels only.
      private var logoMask: some View {
          Image("BMCHelixLogo")
              .resizable()
              .scaledToFit()
              .frame(width: 200)
      }

      // MARK: - Animation

      private func startAnimations() {
          // Shimmer
          if !reduceMotion {
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                  withAnimation(.easeInOut(duration: 0.8)) {
                      shimmerOffset = 200
                  }
              }
          }

          // Fade out
          DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
              if reduceMotion {
                  splashOpacity = 0
              } else {
                  withAnimation(.easeInOut(duration: 0.5)) {
                      splashOpacity = 0
                  }
              }
          }

          // Remove from hierarchy
          DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
              onDismiss()
          }
      }
  }

  #Preview {
      SplashView(onDismiss: {})
  }
  ```

- [ ] **Step 2: Build to verify it compiles**

  Run: `./build_and_deploy.sh`

  Expected: Build succeeds. (The splash won't appear yet — `BeNeMApp` hasn't been wired up.)

- [ ] **Step 3: Commit**

  ```bash
  git add BeNeM/Views/SplashView.swift
  git commit -m "feat: add SplashView with glass effect and shimmer animation"
  ```

---

### Task 3: Wire SplashView into BeNeMApp

**Files:**
- Modify: `BeNeM/BeNeMApp.swift`

**What changes:** Add a `@State` flag and overlay `SplashView` on `ContentView`. When `SplashView` calls `onDismiss`, the flag is set to `false` and the overlay is removed.

- [ ] **Step 1: Update `BeNeM/BeNeMApp.swift`**

  Replace the entire file content with:

  ```swift
  import SwiftUI

  @main
  struct BeNeMApp: App {
      @State private var showSplash = true

      var body: some Scene {
          WindowGroup {
              ContentView()
                  .overlay {
                      if showSplash {
                          SplashView {
                              showSplash = false
                          }
                      }
                  }
          }
      }
  }
  ```

- [ ] **Step 2: Build and deploy to device**

  Run: `./build_and_deploy.sh`

  Expected: Build succeeds and app installs on device.

- [ ] **Step 3: Manual verification on device**

  Kill the app fully (swipe up from app switcher), then relaunch. Verify:
  1. Black screen appears immediately on launch (no white flash)
  2. BMCHelixLogo is visible and centered
  3. Shimmer sweep animates across the logo once (~0.8 s)
  4. After ~1 s the splash fades out smoothly
  5. Dashboard (Tactical Overview) is visible and interactive after ~1.5 s
  6. Bringing the app to foreground from background does NOT show the splash again

- [ ] **Step 4: Commit**

  ```bash
  git add BeNeM/BeNeMApp.swift
  git commit -m "feat: wire SplashView into BeNeMApp on launch"
  ```
