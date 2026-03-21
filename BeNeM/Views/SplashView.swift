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
