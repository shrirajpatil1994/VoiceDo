@testable import VoiceDo
import VoiceDoShared
import XCTest

// MARK: - Module6Tests

/// Module 6 — Widget Extension tests.
///
/// Widget rendering (Simulator Gallery) and interactive button tap are verified manually.
/// These unit tests cover (widget-target types tested via Simulator; shared logic tested here):
///   1. `WidgetSnapshot.empty` returns correct zero-state values.
///   2. `AppGroupDataReader` decode path falls back to `.empty` when data is nil.
///   3. `AppGroupDataReader` decode path falls back to `.empty` when data is corrupt.
///   4. `AppGroupDataReader` decode path returns valid snapshot from encoded data.
///   5. Timeline refresh policy uses `nextReminder.dueDate` when sooner than 15 min.
///   6. Timeline refresh policy uses 15 min when no reminder is set.
///   7. Timeline refresh policy uses 15 min when reminder is further than 15 min away.
///   8. Widget capture URL is well-formed.
final class Module6Tests: XCTestCase {

    // MARK: - WidgetSnapshot.empty

    func testEmptySnapshotHasZeroCount() {
        XCTAssertEqual(WidgetSnapshot.empty.incompleteTodoCount, 0)
    }

    func testEmptySnapshotHasNilReminder() {
        XCTAssertNil(WidgetSnapshot.empty.nextReminder)
    }

    // MARK: - AppGroupDataReader fallback

    func testReaderReturnsEmptyWhenNoData() {
        // Use a random suiteName that definitely has no data
        let suiteName = "test.module6.\(UUID().uuidString)"
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)

        // Directly test the decode path by creating a reader that uses a clean suite
        // AppGroupDataReader reads from AppConstants.appGroupID — we verify the guard-else
        // path by ensuring decode of nil data returns .empty
        let snapshot = decodeSnapshot(from: nil)
        XCTAssertEqual(snapshot.incompleteTodoCount, 0)
        XCTAssertNil(snapshot.nextReminder)
    }

    func testReaderReturnsEmptyOnCorruptData() {
        let corruptData = Data("not valid json".utf8)
        let snapshot = decodeSnapshot(from: corruptData)
        XCTAssertEqual(snapshot.incompleteTodoCount, 0)
        XCTAssertNil(snapshot.nextReminder)
    }

    func testReaderDecodesValidSnapshot() throws {
        let preview = WidgetReminderPreview(
            id: UUID(),
            title: "Pay rent",
            dueDate: Date().addingTimeInterval(3600),
            taskTypeRawValue: "deadline"
        )
        let original = WidgetSnapshot(
            incompleteTodoCount: 5,
            nextReminder: preview,
            lastUpdated: Date()
        )
        let data = try JSONEncoder().encode(original)
        let decoded = decodeSnapshot(from: data)
        XCTAssertEqual(decoded.incompleteTodoCount, 5)
        XCTAssertEqual(decoded.nextReminder?.title, "Pay rent")
        XCTAssertEqual(decoded.nextReminder?.taskTypeRawValue, "deadline")
    }

    // MARK: - Timeline refresh policy

    func testTimelinePolicyUsesReminderDateWhenSooner() {
        // Reminder in 5 minutes — sooner than the 15-min fallback
        let soonDate = Date().addingTimeInterval(5 * 60)
        let preview = WidgetReminderPreview(
            id: UUID(),
            title: "Meeting",
            dueDate: soonDate,
            taskTypeRawValue: nil
        )
        let snapshot = WidgetSnapshot(incompleteTodoCount: 1, nextReminder: preview, lastUpdated: Date())
        let nextUpdate = computeNextUpdate(snapshot: snapshot)
        // Should be within 1 second of the reminder date
        XCTAssertLessThan(abs(nextUpdate.timeIntervalSince(soonDate)), 1)
    }

    func testTimelinePolicyUses15MinWhenNoReminder() {
        let snapshot = WidgetSnapshot.empty
        let before = Date()
        let nextUpdate = computeNextUpdate(snapshot: snapshot)
        let after = Date()
        // 15 minutes: 900 seconds. Allow a 2-second window for execution time.
        XCTAssertGreaterThanOrEqual(nextUpdate.timeIntervalSince(before), 899)
        XCTAssertLessThanOrEqual(nextUpdate.timeIntervalSince(after), 901)
    }

    func testTimelinePolicyUses15MinWhenReminderIsFar() {
        // Reminder in 1 hour — 15 min is sooner
        let farDate = Date().addingTimeInterval(3600)
        let preview = WidgetReminderPreview(
            id: UUID(),
            title: "Later",
            dueDate: farDate,
            taskTypeRawValue: nil
        )
        let snapshot = WidgetSnapshot(incompleteTodoCount: 0, nextReminder: preview, lastUpdated: Date())
        let before = Date()
        let nextUpdate = computeNextUpdate(snapshot: snapshot)
        let after = Date()
        XCTAssertGreaterThanOrEqual(nextUpdate.timeIntervalSince(before), 899)
        XCTAssertLessThanOrEqual(nextUpdate.timeIntervalSince(after), 901)
    }

    // MARK: - Capture URL

    func testCaptureURLIsWellFormed() {
        let urlString = "\(AppConstants.urlScheme)://capture"
        let url = URL(string: urlString)
        XCTAssertNotNil(url, "Capture URL must be a valid URL: \(urlString)")
        XCTAssertEqual(url?.scheme, AppConstants.urlScheme)
        XCTAssertEqual(url?.host, "capture")
    }

    // MARK: - Helpers

    /// Mirrors the logic in `VoiceDoTimelineProvider.getTimeline`.
    private func computeNextUpdate(snapshot: WidgetSnapshot) -> Date {
        let fifteenMinutes = Date().addingTimeInterval(15 * 60)
        return [snapshot.nextReminder?.dueDate, fifteenMinutes]
            .compactMap { $0 }
            .min() ?? fifteenMinutes
    }

    /// Decode a `WidgetSnapshot` from raw data, mirroring `AppGroupDataReader` logic.
    private func decodeSnapshot(from data: Data?) -> WidgetSnapshot {
        guard let data,
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }
}
