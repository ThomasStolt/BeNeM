import SwiftUI

struct SplashView: View {
    var onDismiss: () -> Void

    @State private var shimmerOffset: CGFloat = -240
    @State private var logoOpacity: Double = 0.0
    @State private var splashOpacity: Double = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color("SplashBackground").ignoresSafeArea()

            Image("BMCHelixLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 240)
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
                        .init(color: .white.opacity(0.9), location: 0.5),
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
        Image("BMCHelixLogo")
            .resizable()
            .scaledToFit()
            .frame(width: 240)
    }

    // MARK: - Animation
    // Timeline:
    //   0.0 s — fade-in starts (1.0 s)
    //   1.0 s — logo fully visible, shimmer starts (2.2 s sweep across 2 s visible window)
    //   3.0 s — fade-out starts (1.0 s)
    //   4.0 s — dismiss

    private func startAnimations() {
        // Fade in logo
        if reduceMotion {
            logoOpacity = 1.0
        } else {
            withAnimation(.easeIn(duration: 1.0)) {
                logoOpacity = 1.0
            }
        }

        // Shimmer: start after fade-in completes
        if !reduceMotion {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeInOut(duration: 2.2)) {
                    shimmerOffset = 240
                }
            }
        }

        // Fade out
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if reduceMotion {
                splashOpacity = 0
            } else {
                withAnimation(.easeOut(duration: 1.0)) {
                    splashOpacity = 0
                }
            }
        }

        // Remove from hierarchy
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            onDismiss()
        }
    }
}

#Preview {
    SplashView(onDismiss: {})
}
