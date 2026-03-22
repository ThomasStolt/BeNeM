import SwiftUI

struct SplashView: View {
    var onDismiss: () -> Void

    @State private var shimmerOffset: CGFloat = -288
    @State private var logoOpacity: Double = 0.0
    @State private var splashOpacity: Double = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color("SplashBackground").ignoresSafeArea()

            Image("SplashLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 288)
                .overlay(shimmerBand.mask(logoMask))
                .opacity(logoOpacity)
        }
        .opacity(splashOpacity)
        .onAppear(perform: startAnimations)
    }

    // MARK: - Shimmer

    private var shimmerBand: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: Color(red: 1.0, green: 0.85, blue: 0.3).opacity(0.9), location: 0.5),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 60, height: 400)
            .rotationEffect(.degrees(20))
            .offset(x: shimmerOffset)
    }

    private var logoMask: some View {
        Image("SplashLogo")
            .resizable()
            .scaledToFit()
            .frame(width: 288)
    }

    // MARK: - Animation
    // Timeline:
    //   0.0 s — fade-in starts (0.9 s)
    //   0.9 s — logo fully visible, shimmer starts (2.0 s sweep across 1.8 s visible window)
    //   2.7 s — fade-out starts (0.9 s)
    //   3.6 s — dismiss

    private func startAnimations() {
        // Fade in logo
        if reduceMotion {
            logoOpacity = 1.0
        } else {
            withAnimation(.easeIn(duration: 0.9)) {
                logoOpacity = 1.0
            }
        }

        // Shimmer: start after fade-in completes
        if !reduceMotion {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                withAnimation(.easeInOut(duration: 2.0)) {
                    shimmerOffset = 288
                }
            }
        }

        // Fade out
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.7) {
            if reduceMotion {
                splashOpacity = 0
            } else {
                withAnimation(.easeOut(duration: 0.9)) {
                    splashOpacity = 0
                }
            }
        }

        // Remove from hierarchy
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) {
            onDismiss()
        }
    }
}

#Preview {
    SplashView(onDismiss: {})
}
