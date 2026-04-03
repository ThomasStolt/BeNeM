import SwiftUI

struct MarqueeText: View {
    let text: String
    var font: Font = .body
    var fontWeight: Font.Weight = .regular
    var color: Color = .primary
    var speed: Double = 30 // points per second

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var animating = false

    private var needsScroll: Bool { textWidth > containerWidth && containerWidth > 0 }

    var body: some View {
        GeometryReader { geo in
            let cw = geo.size.width
            Text(text)
                .font(font)
                .fontWeight(fontWeight)
                .foregroundColor(color)
                .fixedSize()
                .background(GeometryReader { inner in
                    Color.clear.onAppear {
                        textWidth = inner.size.width
                        containerWidth = cw
                        startAnimationIfNeeded()
                    }
                })
                .offset(x: offset)
        }
        .clipped()
        .frame(height: fontHeight)
    }

    private var fontHeight: CGFloat {
        switch font {
        case .headline: return 22
        case .subheadline: return 18
        case .caption: return 14
        default: return 20
        }
    }

    private func startAnimationIfNeeded() {
        guard needsScroll, !animating else { return }
        animating = true
        let overflow = textWidth - containerWidth
        let duration = Double(overflow + 40) / speed

        // Pause, scroll left, pause, snap back, repeat
        func cycle() {
            offset = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.linear(duration: duration)) {
                    offset = -overflow - 20
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + duration + 1.0) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        offset = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        cycle()
                    }
                }
            }
        }
        cycle()
    }
}
