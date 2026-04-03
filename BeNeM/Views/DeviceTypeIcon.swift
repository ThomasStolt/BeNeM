import SwiftUI

struct DeviceTypeIcon: View {
    let typeClass: DeviceTypeClass
    var size: CGFloat = 60
    var color: Color = .green

    var body: some View {
        Group {
            switch typeClass {
            case .linux:
                linuxIcon
            case .windows:
                windowsIcon
            case .router:
                routerIcon
            case .switchDevice:
                switchIcon
            case .unknown:
                unknownIcon
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: - Linux Penguin (Tux)

    private var linuxIcon: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let cx = w / 2
            let inset: CGFloat = 0.12
            let drawW = w * (1 - inset * 2)
            let drawH = h * (1 - inset * 2)
            let ox = w * inset
            let oy = h * inset

            // Body (dark oval)
            let bodyRect = CGRect(x: ox + drawW * 0.15, y: oy + drawH * 0.25,
                                  width: drawW * 0.7, height: drawH * 0.72)
            let bodyPath = Ellipse().path(in: bodyRect)
            context.fill(bodyPath, with: .color(color.opacity(0.85)))

            // Belly (lighter inner oval)
            let bellyRect = CGRect(x: ox + drawW * 0.28, y: oy + drawH * 0.38,
                                   width: drawW * 0.44, height: drawH * 0.52)
            let bellyPath = Ellipse().path(in: bellyRect)
            context.fill(bellyPath, with: .color(Color(.systemBackground).opacity(0.85)))

            // Head (circle)
            let headSize = drawW * 0.52
            let headRect = CGRect(x: cx - headSize / 2, y: oy + drawH * 0.02,
                                  width: headSize, height: headSize)
            let headPath = Circle().path(in: headRect)
            context.fill(headPath, with: .color(color.opacity(0.85)))

            // Eyes (two small white circles with dark pupils)
            let eyeSize = drawW * 0.1
            let eyeY = oy + drawH * 0.13
            let leftEyeRect = CGRect(x: cx - drawW * 0.14, y: eyeY,
                                     width: eyeSize, height: eyeSize)
            let rightEyeRect = CGRect(x: cx + drawW * 0.04, y: eyeY,
                                      width: eyeSize, height: eyeSize)
            context.fill(Circle().path(in: leftEyeRect), with: .color(.white))
            context.fill(Circle().path(in: rightEyeRect), with: .color(.white))

            let pupilSize = eyeSize * 0.5
            let pupilOffset = (eyeSize - pupilSize) / 2
            let leftPupil = CGRect(x: leftEyeRect.midX - pupilSize / 2 + pupilOffset * 0.3,
                                   y: leftEyeRect.midY - pupilSize / 2,
                                   width: pupilSize, height: pupilSize)
            let rightPupil = CGRect(x: rightEyeRect.midX - pupilSize / 2 - pupilOffset * 0.3,
                                    y: rightEyeRect.midY - pupilSize / 2,
                                    width: pupilSize, height: pupilSize)
            context.fill(Circle().path(in: leftPupil), with: .color(color))
            context.fill(Circle().path(in: rightPupil), with: .color(color))

            // Beak (small orange triangle)
            var beakPath = Path()
            let beakY = oy + drawH * 0.21
            beakPath.move(to: CGPoint(x: cx - drawW * 0.06, y: beakY))
            beakPath.addLine(to: CGPoint(x: cx + drawW * 0.06, y: beakY))
            beakPath.addLine(to: CGPoint(x: cx, y: beakY + drawH * 0.06))
            beakPath.closeSubpath()
            context.fill(beakPath, with: .color(.orange))

            // Feet (two small orange ovals)
            let footW = drawW * 0.18
            let footH = drawH * 0.06
            let footY = oy + drawH * 0.92
            let leftFoot = CGRect(x: cx - drawW * 0.22, y: footY, width: footW, height: footH)
            let rightFoot = CGRect(x: cx + drawW * 0.04, y: footY, width: footW, height: footH)
            context.fill(Ellipse().path(in: leftFoot), with: .color(.orange))
            context.fill(Ellipse().path(in: rightFoot), with: .color(.orange))
        }
    }

    // MARK: - Windows

    private var windowsIcon: some View {
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height) * 0.7
            let origin = CGPoint(x: (canvasSize.width - s) / 2, y: (canvasSize.height - s) / 2)
            let gap: CGFloat = s * 0.06

            // Four panes of the Windows logo
            let halfW = (s - gap) / 2
            let halfH = (s - gap) / 2

            let panes = [
                CGRect(x: origin.x, y: origin.y, width: halfW, height: halfH),
                CGRect(x: origin.x + halfW + gap, y: origin.y, width: halfW, height: halfH),
                CGRect(x: origin.x, y: origin.y + halfH + gap, width: halfW, height: halfH),
                CGRect(x: origin.x + halfW + gap, y: origin.y + halfH + gap, width: halfW, height: halfH),
            ]
            for pane in panes {
                let path = RoundedRectangle(cornerRadius: 2).path(in: pane)
                context.fill(path, with: .color(color))
            }
        }
    }

    // MARK: - Router (arrows pointing out from center, rounded square background)

    private var routerIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18)
                .fill(color)
                .frame(width: size * 0.85, height: size * 0.85)

            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .resizable()
                .scaledToFit()
                .foregroundColor(Color(.systemBackground).opacity(0.85))
                .fontWeight(.bold)
                .frame(width: size * 0.5, height: size * 0.5)
        }
    }

    // MARK: - Switch (crossing arrows, circle background)

    private var switchIcon: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: size * 0.85, height: size * 0.85)

            Image(systemName: "arrow.triangle.swap")
                .resizable()
                .scaledToFit()
                .foregroundColor(Color(.systemBackground).opacity(0.85))
                .fontWeight(.bold)
                .frame(width: size * 0.45, height: size * 0.45)
        }
    }

    // MARK: - Unknown

    private var unknownIcon: some View {
        Image(systemName: "desktopcomputer")
            .resizable()
            .scaledToFit()
            .foregroundColor(color)
            .padding(size * 0.1)
    }
}
