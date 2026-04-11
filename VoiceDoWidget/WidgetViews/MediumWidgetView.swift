import AppIntents
import SwiftUI
import VoiceDoShared
import WidgetKit

/// 4×2 medium widget: next reminder + todo count (left) + mic button (right).
/// Mic button uses `Link` with the `voicedo://capture` URL scheme.
struct MediumWidgetView: View {

    let entry: VoiceDoEntry

    private static let captureURL = URL(string: "\(AppConstants.urlScheme)://capture")

    var body: some View {
        HStack(spacing: 0) {
            infoPanel
            Spacer(minLength: 0)
            micPanel
        }
    }

    // MARK: - Sub-views

    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("VoiceDo")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(white: 0.52))
                .kerning(0.5)

            Rectangle()
                .fill(Color(white: 0.86))
                .frame(height: 0.5)

            if let reminder = entry.snapshot.nextReminder {
                VStack(alignment: .leading, spacing: 3) {
                    Label {
                        Text(reminder.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color(white: 0.08))
                            .lineLimit(2)
                    } icon: {
                        Image(systemName: reminderIcon(for: reminder.taskTypeRawValue))
                            .font(.system(size: 12))
                            .foregroundStyle(Color(white: 0.35))
                    }
                    Text(reminder.dueDate, style: .relative)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(white: 0.52))
                }
            } else {
                Text("No upcoming reminders")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(white: 0.52))
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Image(systemName: "checklist")
                    .font(.system(size: 11))
                let count = entry.snapshot.incompleteTodoCount
                Text("\(count) task\(count == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Color(white: 0.35))
        }
        .frame(maxHeight: .infinity, alignment: .leading)
        .padding(.leading, 16)
        .padding(.vertical, 14)
    }

    private var micPanel: some View {
        VStack {
            Spacer()
            if let url = Self.captureURL {
                Link(destination: url) {
                    micButtonContent
                }
                .accessibilityLabel("Capture voice note")
            } else {
                micButtonContent
            }
            Spacer()
        }
        .padding(.trailing, 16)
    }

    private var micButtonContent: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.08))
                .frame(width: 56, height: 56)
            Image(systemName: "mic.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Helpers

    private func reminderIcon(for rawValue: String?) -> String {
        switch rawValue {
        case "message": return "envelope"
        case "purchase": return "cart"
        case "deadline": return "calendar.badge.exclamationmark"
        case "call": return "phone"
        default: return "bell"
        }
    }
}
