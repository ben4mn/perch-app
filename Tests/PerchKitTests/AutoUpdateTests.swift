import XCTest
@testable import PerchKit

/// Perch keeps itself up to date on every Mac it's on without being asked: it looks for a new version every
/// few hours as well as at launch, downloads it in the background, and puts it in place only when it restarts,
/// which it does once nobody has used it for a minute (or when it is quit), reopening in the background.
final class AutoUpdateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testItLooksAgainEveryFewHours() {
        XCTAssertTrue(AutoUpdate.dueForCheck(lastCheck: nil, now: now), "never looked: look now")
        XCTAssertFalse(AutoUpdate.dueForCheck(lastCheck: now.addingTimeInterval(-3_600), now: now))
        XCTAssertTrue(AutoUpdate.dueForCheck(lastCheck: now.addingTimeInterval(-AutoUpdate.checkEvery - 1), now: now))
    }

    func testItNeverRestartsWhileSomeoneIsUsingIt() {
        XCTAssertFalse(AutoUpdate.canRestart(isActive: true, inactiveSince: nil, now: now))
        XCTAssertFalse(AutoUpdate.canRestart(isActive: true, inactiveSince: now.addingTimeInterval(-600), now: now),
                       "in front again: not now, however long it was away")
    }

    func testItRestartsOnceItHasBeenInTheBackgroundAMinute() {
        XCTAssertFalse(AutoUpdate.canRestart(isActive: false, inactiveSince: now.addingTimeInterval(-20), now: now))
        XCTAssertTrue(AutoUpdate.canRestart(isActive: false, inactiveSince: now.addingTimeInterval(-AutoUpdate.quietFor - 1), now: now))
        // In the background since launch, with no time recorded: counts from when the update was ready.
        XCTAssertFalse(AutoUpdate.canRestart(isActive: false, inactiveSince: nil, now: now))
    }
}
