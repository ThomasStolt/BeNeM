// BeNeM/Views/FloppyDiskIcon.swift
import SwiftUI

/// Classic 3.5" floppy disk icon drawn as a SwiftUI Shape.
struct FloppyDiskIcon: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let r = w * 0.12 // corner radius

            Canvas { ctx, size in
                // Body — rounded rectangle
                let body = RoundedRectangle(cornerRadius: r)
                    .path(in: CGRect(origin: .zero, size: size))
                ctx.fill(body, with: .foreground)

                // Metal slider — top center notch (darker inset)
                let sliderW = w * 0.44
                let sliderH = h * 0.28
                let sliderX = (w - sliderW) / 2
                let slider = RoundedRectangle(cornerRadius: r * 0.5)
                    .path(in: CGRect(x: sliderX, y: 0, width: sliderW, height: sliderH))
                ctx.blendMode = .destinationOut
                ctx.fill(slider, with: .foreground)
                ctx.blendMode = .normal
                ctx.fill(slider, with: .color(.primary.opacity(0.25)))

                // Slider slot — thin vertical line in metal slider
                let slotW = w * 0.06
                let slotX = sliderX + sliderW * 0.35
                let slotY = h * 0.04
                let slotH = sliderH - slotY * 2
                let slot = Rectangle()
                    .path(in: CGRect(x: slotX, y: slotY, width: slotW, height: slotH))
                ctx.blendMode = .destinationOut
                ctx.fill(slot, with: .foreground)

                // Label area — bottom rectangle (lighter inset)
                ctx.blendMode = .normal
                let labelW = w * 0.72
                let labelH = h * 0.36
                let labelX = (w - labelW) / 2
                let labelY = h - labelH - h * 0.06
                let label = RoundedRectangle(cornerRadius: r * 0.4)
                    .path(in: CGRect(x: labelX, y: labelY, width: labelW, height: labelH))
                ctx.fill(label, with: .color(.primary.opacity(0.15)))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
