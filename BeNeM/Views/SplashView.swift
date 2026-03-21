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
            // Shimmer clipped to logo pixels
            .overlay(shimmerBand.mask(logoMask))
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.easeInOut(duration: 2.2)) {
                    shimmerOffset = 200
                }
            }
        }

        // Fade out
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if reduceMotion {
                splashOpacity = 0
            } else {
                withAnimation(.easeInOut(duration: 1.0)) {
                    splashOpacity = 0
                }
            }
        }

        // Remove from hierarchy
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            onDismiss()
        }
    }
}

#Preview {
    SplashView(onDismiss: {})
}
