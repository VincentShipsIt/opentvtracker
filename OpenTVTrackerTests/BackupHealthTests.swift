import XCTest
@testable import OpenTVTracker

final class BackupHealthTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testMissingTimestampHasNoCompleteBackup() {
        XCTAssertNil(BackupHealth.lastSuccessfulExportAt(from: 0))
        XCTAssertEqual(
            BackupHealth.state(lastSuccessfulExportAt: nil, now: now),
            .neverExported
        )
    }

    func testBackupRemainsCurrentBeforeThirtyDays() {
        let lastExportedAt = now.addingTimeInterval(-(BackupHealth.reminderInterval - 1))

        XCTAssertEqual(
            BackupHealth.state(lastSuccessfulExportAt: lastExportedAt, now: now),
            .current(lastExportedAt: lastExportedAt)
        )
    }

    func testBackupBecomesDueAtThirtyDays() {
        let lastExportedAt = now.addingTimeInterval(-BackupHealth.reminderInterval)

        XCTAssertEqual(
            BackupHealth.state(lastSuccessfulExportAt: lastExportedAt, now: now),
            .due(lastExportedAt: lastExportedAt)
        )
    }

    func testFutureTimestampFromClockCorrectionRemainsCurrent() {
        let lastExportedAt = now.addingTimeInterval(60)

        XCTAssertEqual(
            BackupHealth.state(lastSuccessfulExportAt: lastExportedAt, now: now),
            .current(lastExportedAt: lastExportedAt)
        )
    }

    func testOnlyCompleteJSONSatisfiesBackupReminder() {
        XCTAssertTrue(LibraryExportKind.json.completesBackup)
        XCTAssertFalse(LibraryExportKind.titlesCSV.completesBackup)
        XCTAssertFalse(LibraryExportKind.eventsCSV.completesBackup)
    }
}
