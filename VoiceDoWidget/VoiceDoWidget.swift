import AppIntents
import SwiftUI
import VoiceDoShared
import WidgetKit

// MARK: - Timeline Entry

struct VoiceDoEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let workspace: WorkspaceOption
}

// MARK: - TimelineProvider

struct VoiceDoTimelineProvider: AppIntentTimelineProvider {

    private let reader = AppGroupDataReader()

    func placeholder(in context: Context) -> VoiceDoEntry {
        VoiceDoEntry(
            date: Date(),
            snapshot: WidgetSnapshot(
                incompleteTodoCount: 3,
                nextReminder: WidgetReminderPreview(
                    id: UUID(),
                    title: "Call Sarah",
                    dueDate: Date().addingTimeInterval(7200),
                    taskTypeRawValue: "call"
                ),
                lastUpdated: Date()
            ),
            workspace: .all
        )
    }

    func snapshot(
        for configuration: VoiceDoWidgetIntent,
        in context: Context
    ) async -> VoiceDoEntry {
        VoiceDoEntry(
            date: Date(),
            snapshot: reader.readSnapshot(),
            workspace: configuration.workspace
        )
    }

    func timeline(
        for configuration: VoiceDoWidgetIntent,
        in context: Context
    ) async -> Timeline<VoiceDoEntry> {
        let snapshot = reader.readSnapshot()
        let entry = VoiceDoEntry(date: Date(), snapshot: snapshot, workspace: configuration.workspace)

        // Reload at the next reminder due date, or in 15 minutes — whichever is sooner.
        let fifteenMinutes = Date().addingTimeInterval(15 * 60)
        let nextUpdate = [snapshot.nextReminder?.dueDate, fifteenMinutes]
            .compactMap { $0 }
            .min() ?? fifteenMinutes

        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
}

// MARK: - Widget Bundle

@main
struct VoiceDoWidgetBundle: WidgetBundle {
    var body: some Widget {
        VoiceDoWidgetSmall()
    }
}

// MARK: - Small Widget

struct VoiceDoWidgetSmall: Widget {
    let kind: String = AppConstants.widgetKind + "_small"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: VoiceDoWidgetIntent.self,
            provider: VoiceDoTimelineProvider()
        ) { entry in
            SmallWidgetView(entry: entry)
                .containerBackground(
                    Color(red: 0.969, green: 0.957, blue: 0.937),
                    for: .widget
                )
        }
        .configurationDisplayName("VoiceDo")
        .description("Tap to capture a voice note.")
        .supportedFamilies([.systemSmall])
    }
}
