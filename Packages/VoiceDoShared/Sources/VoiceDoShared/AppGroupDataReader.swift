import Foundation

// MARK: - AppGroupDataReader

/// Read-only accessor for the App Group `WidgetSnapshot`.
/// Used by the widget extension's `TimelineProvider`.
/// Lives in the shared package so both the app and widget targets can reference it.
public struct AppGroupDataReader: Sendable {

    public init() {}

    public func readSnapshot() -> WidgetSnapshot {
        guard let defaults = UserDefaults(suiteName: AppConstants.appGroupID),
              let data = defaults.data(forKey: AppConstants.widgetSnapshotKey),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }
}
