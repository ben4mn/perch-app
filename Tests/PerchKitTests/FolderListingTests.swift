import XCTest
@testable import PerchKit

final class FolderListingTests: XCTestCase {
    private func date(_ day: Int) -> Date { Date(timeIntervalSince1970: Double(day) * 86_400) }

    private var files: [VaultFile] {
        [
            VaultFile(path: "Readme.md", modified: date(1)),
            VaultFile(path: "Sums.ipynb", modified: date(2)),
            VaultFile(path: "Personal/Zebra.md", modified: date(3)),
            VaultFile(path: "Personal/apple.md", modified: date(9)),
            VaultFile(path: "Personal/Plans.kanban.md", modified: date(5)),
            VaultFile(path: "Personal/Sketch.excalidraw", modified: nil),
            VaultFile(path: "Personal/Tasks/Buy milk.md", modified: date(50)),
            VaultFile(path: "Personal/.attachments/photo.png", modified: date(60)),
            VaultFile(path: "Personal/AI Learning/Intro.md", modified: date(4)),
            VaultFile(path: "Personal/AI Learning/React Apps/One.md", modified: date(20)),
            VaultFile(path: "Personal/AI Learning/React Apps/Board.kanban.md", modified: date(7)),
            VaultFile(path: "Personal/Cooking/Soup.md", modified: date(6)),
            VaultFile(path: "PersonalStuff/Other.md", modified: date(8)),
            VaultFile(path: "Work/Tasks/Ship it.md", modified: date(70)),
        ]
    }

    func testTopLevelListsFoldersAndFiles() {
        let listing = FolderListing(files: files, path: "")
        XCTAssertEqual(listing.folders.map(\.name), ["Personal", "PersonalStuff"], "A folder holding only tasks is left out")
        XCTAssertEqual(listing.files.map(\.path), ["Readme.md", "Sums.ipynb"])
        XCTAssertEqual(listing.itemCount, 11)
        XCTAssertEqual(listing.summary, "2 folders · 1 note · 1 notebook")
    }

    func testCountsAndLatestChangeAreRecursive() throws {
        let listing = FolderListing(files: files, path: "Personal")
        XCTAssertEqual(listing.folders.map(\.name), ["AI Learning", "Cooking"], "Tasks and attachments folders stay hidden")
        let learning = try XCTUnwrap(listing.folders.first)
        XCTAssertEqual(learning.path, "Personal/AI Learning")
        XCTAssertEqual(learning.itemCount, 3)
        XCTAssertEqual(learning.modified, date(20))
        XCTAssertEqual(listing.files.map(\.title), ["apple", "Plans", "Sketch", "Zebra"])
        XCTAssertEqual(listing.summary, "2 folders · 2 notes · 1 board · 1 whiteboard")
    }

    func testFolderNamePrefixIsNotAMatch() {
        let listing = FolderListing(files: files, path: "Personal")
        XCTAssertFalse(listing.files.contains { $0.path.hasPrefix("PersonalStuff") })
        XCTAssertEqual(FolderListing(files: files, path: "Personal/").path, "Personal")
    }

    func testSortByLastModifiedPutsNewestFirstAndUndatedLast() {
        let listing = FolderListing(files: files, path: "Personal", sort: .modified)
        XCTAssertEqual(listing.files.map(\.title), ["apple", "Plans", "Zebra", "Sketch"])
        XCTAssertEqual(listing.folders.map(\.name), ["AI Learning", "Cooking"])
    }

    func testSortByKindGroupsFiles() {
        let listing = FolderListing(files: files, path: "Personal", sort: .kind)
        XCTAssertEqual(listing.files.map(\.title), ["apple", "Zebra", "Plans", "Sketch"])
    }

    func testKindsFilterKeepsOnlyFoldersWithMatches() {
        let top = FolderListing(files: files, path: "", kinds: [.board])
        XCTAssertEqual(top.folders.map(\.name), ["Personal"])
        XCTAssertEqual(top.folders.first?.itemCount, 2)
        XCTAssertTrue(top.files.isEmpty)

        let personal = FolderListing(files: files, path: "Personal", kinds: [.board])
        XCTAssertEqual(personal.folders.map(\.name), ["AI Learning"])
        XCTAssertEqual(personal.files.map(\.title), ["Plans"])
        XCTAssertEqual(personal.summary, "1 folder · 1 board")
    }

    func testMissingFolderIsEmpty() {
        let listing = FolderListing(files: files, path: "Nowhere")
        XCTAssertTrue(listing.isEmpty)
        XCTAssertEqual(listing.summary, "Empty")
        XCTAssertEqual(listing.itemCount, 0)
    }

    func testSameTitleKeepsOneOrderHoweverTheFilesArrive() {
        let twins = [
            VaultFile(path: "Plans.md", modified: date(1)),
            VaultFile(path: "Plans.kanban.md", modified: date(1)),
            VaultFile(path: "Plans.excalidraw", modified: date(1)),
        ]
        for sort in FolderListing.Sort.allCases {
            let forwards = FolderListing(files: twins, path: "", sort: sort).files.map(\.path)
            let backwards = FolderListing(files: twins.reversed(), path: "", sort: sort).files.map(\.path)
            XCTAssertEqual(forwards, backwards, "\(sort)")
        }
    }

    func testEmojiAndSpacesInFolderNames() {
        let files = [
            VaultFile(path: "✈️ Acme/README.md"),
            VaultFile(path: "✈️ Acme/_Now/This week.md"),
            VaultFile(path: "✈️ Acme/Tasks/Book flights.md"),
            VaultFile(path: "✈️ Acme Old/Note.md"),
        ]
        XCTAssertEqual(FolderListing(files: files, path: "").folders.map(\.path), ["✈️ Acme", "✈️ Acme Old"])
        let listing = FolderListing(files: files, path: "✈️ Acme")
        XCTAssertEqual(listing.folders.map(\.path), ["✈️ Acme/_Now"])
        XCTAssertEqual(listing.files.map(\.title), ["README"])
        XCTAssertEqual(FolderListing.crumbs(for: "✈️ Acme/_Now").map(\.name), ["✈️ Acme", "_Now"])
    }

    func testFolderHoldingOnlyTasksIsEmpty() {
        let listing = FolderListing(files: files, path: "Work")
        XCTAssertTrue(listing.isEmpty)
        XCTAssertTrue(FolderListing(files: files, path: "Personal/Tasks").isEmpty)
    }

    func testCrumbs() {
        XCTAssertEqual(FolderListing.crumbs(for: ""), [])
        XCTAssertEqual(
            FolderListing.crumbs(for: "Personal/AI Learning/React Apps").map(\.path),
            ["Personal", "Personal/AI Learning", "Personal/AI Learning/React Apps"]
        )
        XCTAssertEqual(FolderListing.crumbs(for: "Personal/AI Learning").map(\.name), ["Personal", "AI Learning"])
    }

    // MARK: Created and last edited

    private var dated: [VaultFile] {
        [
            // A fresh copy: every file's disk time is day 100, Git knows the real dates.
            VaultFile(path: "Old.md", modified: date(100), created: date(1), edited: date(40)),
            VaultFile(path: "Recent.md", modified: date(100), created: date(95), edited: date(98)),
            VaultFile(path: "Unsynced.md", modified: date(99), created: date(99)),
            VaultFile(path: "Trips/Rome.md", modified: date(100), created: date(10), edited: date(97)),
            VaultFile(path: "Trips/Oslo.md", modified: date(100), created: date(96), edited: date(96)),
        ]
    }

    func testLastEditedUsesGitsDateNotTheCopysAndCreatedSortsByCreation() {
        let edited = FolderListing(files: dated, path: "", sort: .modified)
        XCTAssertEqual(edited.files.map(\.path), ["Unsynced.md", "Recent.md", "Old.md"])
        XCTAssertEqual(edited.folders.first?.modified, date(97), "a folder is as new as its newest edit")
        let created = FolderListing(files: dated, path: "", sort: .created)
        XCTAssertEqual(created.files.map(\.path), ["Unsynced.md", "Recent.md", "Old.md"])
        XCTAssertEqual(created.folders.first?.created, date(96), "and as new as its newest file")
        let byCreation = FolderListing(files: dated, path: "Trips", sort: .created).files.map(\.path)
        XCTAssertEqual(byCreation, ["Trips/Oslo.md", "Trips/Rome.md"])
        let byEdit = FolderListing(files: dated, path: "Trips", sort: .modified).files.map(\.path)
        XCTAssertEqual(byEdit, ["Trips/Rome.md", "Trips/Oslo.md"])
    }

    func testDateFilterKeepsOnlyFilesInRangeAndFoldersHoldingThem() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let now = date(100).addingTimeInterval(3600)
        let filter = FolderListing.DateFilter(field: .created, range: .week)
        XCTAssertEqual(filter.start(now: now, calendar: utc), date(94))
        XCTAssertTrue(filter.includes(dated[1], now: now, calendar: utc))
        XCTAssertFalse(filter.includes(dated[0], now: now, calendar: utc))

        let listing = FolderListing(files: dated, path: "", sort: .name, filter: .init(field: .edited, range: .week), now: now)
        XCTAssertEqual(listing.files.map(\.path), ["Recent.md", "Unsynced.md"], "Old.md was last edited on day 40")
        XCTAssertEqual(listing.folders.map(\.itemCount), [2])
        let createdThisWeek = FolderListing(files: dated, path: "", filter: .init(field: .created, range: .week), now: now)
        XCTAssertEqual(createdThisWeek.folders.map(\.itemCount), [1], "Rome was created long ago, only Oslo counts")
        let today = FolderListing(files: dated, path: "", filter: .init(field: .created, range: .today), now: now)
        XCTAssertTrue(today.isEmpty)
    }

    func testDateFilterStorageRoundTripsAndFallsBackToAnyTime() {
        let filter = FolderListing.DateFilter(field: .created, range: .month)
        XCTAssertEqual(FolderListing.DateFilter(storage: filter.storage), filter)
        XCTAssertEqual(filter.title, "Created · Past 30 days")
        XCTAssertEqual(FolderListing.DateFilter(storage: "nonsense"), .anyTime)
        XCTAssertFalse(FolderListing.DateFilter(storage: "edited.any").isActive)
    }
}
