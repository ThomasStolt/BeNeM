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

    // MARK: - Linux Penguin

    private var linuxIcon: some View {
        Image(systemName: "bird.fill")
            .resizable()
            .scaledToFit()
            .foregroundColor(color)
            .padding(size * 0.1)
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
