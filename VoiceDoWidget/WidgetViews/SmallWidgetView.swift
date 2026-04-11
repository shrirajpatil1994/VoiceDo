import SwiftUI
import VoiceDoShared
import WidgetKit

/// 1×1 icon widget — tap opens app and begins voice capture immediately.
struct SmallWidgetView: View {

    let entry: VoiceDoEntry

    private static let captureURL = URL(string: "\(AppConstants.urlScheme)://capture")

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // V-mic logo mark centred in the widget
            VStack(spacing: 4) {
                VMicShape()
                    .stroke(
                        Color(white: 0.08),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: 36, height: 28)

                // Mic capsule below the V
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(white: 0.08))
                    .frame(width: 10, height: 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Workspace label — shown only when a specific workspace is selected
            if entry.workspace != .all {
                Text(entry.workspace.displayName.uppercased())
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color(white: 0.08).opacity(0.45))
                    .kerning(0.5)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            }
        }
        .accessibilityLabel("VoiceDo — tap to record")
        .widgetURL(Self.captureURL)
    }
}

// MARK: - V-Mic Shape

/// Two lines descending from top-left and top-right, meeting at bottom-centre.
struct VMicShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

// MARK: - CountPill (kept for backwards compat)

struct CountPill: View {
    let icon: String
    let count: Int?
    var label: String?
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2)
            Text(label ?? "\(count ?? 0)").font(.caption2.bold())
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.15), in: Capsule())
    }
}
