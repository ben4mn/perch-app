import UniformTypeIdentifiers
import XCTest
@testable import PerchKit

/// The notch's Clips: what kind each clip is, how long it is kept, and how the pane groups it.
final class ClipShelfTests: XCTestCase {
    private typealias Shelf = ClipShelf<String>

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        // A zone well away from UTC, so a local day and a UTC day differ. November has no change of clocks there.
        calendar.timeZone = TimeZone(identifier: "Pacific/Honolulu")!
        return calendar
    }

    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: text)!
    }

    private let hour: TimeInterval = 3600

    private func text(_ value: String, at date: Date) -> Shelf.Item {
        .init(key: .text(value), kind: ClipKind.of(text: value), date: date, payload: value)
    }

    private func file(_ path: String, kind: ClipKind = .file, at date: Date) -> Shelf.Item {
        .init(key: .file(path), kind: kind, date: date, payload: path)
    }

    // MARK: - Kinds

    func testTextIsALinkOnlyWhenAllOfItIsOneWebAddress() {
        let links = ["https://example.com", "http://example.com/a?b=1#c", "  https://example.com/path \n", "HTTPS://Example.com/Path", "http://localhost:8787/mcp"]
        for value in links { XCTAssertEqual(ClipKind.of(text: value), .link, value) }
        let texts = [
            "hello", "", "   ", "example.com", "www.example.com", "https://", "https:///path", "ftp://example.com/file",
            "mailto:alex@example.com", "https://example.com and more", "see https://example.com",
            "https://a.com\nhttps://b.com", "file:///tmp/someone/Desktop",
        ]
        for value in texts { XCTAssertEqual(ClipKind.of(text: value), .text, value) }
    }

    func testAFileIsAnImageWhenItsTypeIsOneAndOtherwiseAFile() {
        for type in [UTType.png, .jpeg, .heic, .tiff, .gif] { XCTAssertEqual(ClipKind.of(fileType: type), .image, type.identifier) }
        for type in [UTType.pdf, .quickTimeMovie, .mpeg4Movie, .folder, .plainText, .zip, .applicationBundle] {
            XCTAssertEqual(ClipKind.of(fileType: type), .file, type.identifier)
        }
        XCTAssertEqual(ClipKind.of(fileType: nil), .file)
    }

    func testAScreenshotsFileNameGivesAnImage() {
        XCTAssertEqual(ClipKind.of(fileType: UTType(filenameExtension: "png")), .image)
        XCTAssertEqual(ClipKind.of(fileType: UTType(filenameExtension: "mov")), .file)
    }

    func testALinkShowsItsSiteThenTheRestOfTheAddress() {
        let link = ClipLink(text: " https://www.github.com/someone/perch/pull/50?tab=files#top ")
        XCTAssertEqual(link?.host, "github.com")
        XCTAssertEqual(link?.rest, "/someone/perch/pull/50?tab=files#top")
        XCTAssertEqual(link?.url.absoluteString, "https://www.github.com/someone/perch/pull/50?tab=files#top")
        XCTAssertEqual(ClipLink(text: "https://example.com/")?.rest, "")
        XCTAssertEqual(ClipLink(text: "https://example.com")?.rest, "")
        XCTAssertEqual(ClipLink(text: "http://localhost:8787/mcp")?.host, "localhost:8787")
        XCTAssertEqual(ClipLink(text: "https://example.com/a%20plan")?.rest, "/a plan")
        XCTAssertNil(ClipLink(text: "hello there"))
    }

    func testALongTextIsCutForItsCardAndTrimmed() {
        XCTAssertEqual(ClipRules.preview(of: "  \n hello\r\nthere \n\n"), "hello\nthere")
        let long = String(repeating: "word ", count: 2000)
        XCTAssertEqual(ClipRules.preview(of: long).count, ClipRules.previewLength)
    }

    // MARK: - Keeping

    func testNewClipsComeFirst() {
        let now = date("2026-11-12T10:00:00")
        var shelf = Shelf()
        shelf.add(text("one", at: now.addingTimeInterval(-20)))
        shelf.add(text("two", at: now.addingTimeInterval(-10)))
        shelf.add(text("three", at: now))
        XCTAssertEqual(shelf.items.map(\.payload), ["three", "two", "one"])
    }

    func testAClipArrivingLateStillTakesItsPlaceByTime() {
        // A screenshot is dated when it was taken, which can be just before a copy noticed first.
        let now = date("2026-11-12T10:00:00")
        var shelf = Shelf()
        shelf.add(text("copied", at: now))
        shelf.add(file("/Shots/Screenshot.png", kind: .image, at: now.addingTimeInterval(-0.5)))
        XCTAssertEqual(shelf.items.map(\.payload), ["copied", "/Shots/Screenshot.png"])
    }

    func testNothingIsKeptOnceItIsTwentyFourHoursOld() {
        let now = date("2026-11-12T10:00:00")
        var shelf = Shelf()
        shelf.add(text("exactly a day", at: now.addingTimeInterval(-24 * hour)))
        shelf.add(text("a second less", at: now.addingTimeInterval(-24 * hour + 1)))
        shelf.add(text("two days", at: now.addingTimeInterval(-48 * hour)))
        XCTAssertTrue(shelf.prune(now: now))
        XCTAssertEqual(shelf.items.map(\.payload), ["a second less"])
        XCTAssertTrue(shelf.prune(now: now.addingTimeInterval(1)))
        XCTAssertTrue(shelf.items.isEmpty)
    }

    func testPruningThatChangesNothingSaysSo() {
        let now = date("2026-11-12T10:00:00")
        var shelf = Shelf()
        shelf.add(text("fresh", at: now))
        XCTAssertFalse(shelf.prune(now: now.addingTimeInterval(60)))
        XCTAssertEqual(shelf.items.count, 1)
    }

    func testCopyingTheSameThingAgainRefreshesItInsteadOfAddingIt() {
        let now = date("2026-11-12T10:00:00")
        var shelf = Shelf()
        let old = shelf.add(text("the address", at: now.addingTimeInterval(-23 * hour)))
        shelf.add(text("something else", at: now.addingTimeInterval(-hour)))
        let again = shelf.add(Shelf.Item(key: .text("the address"), kind: .text, date: now, payload: "a new copy"))
        XCTAssertEqual(shelf.items.map(\.payload), ["the address", "something else"])
        XCTAssertEqual(again.id, old.id, "the clip already here is kept, with what was made for it")
        XCTAssertEqual(shelf.items.first?.date, now)
        // Two hours on, the original copy would be gone; the recopy keeps it.
        shelf.prune(now: now.addingTimeInterval(2 * hour))
        XCTAssertEqual(shelf.items.map(\.payload), ["the address", "something else"])
    }

    func testTheSameImageCopiedTwiceIsOneClip() {
        let now = date("2026-11-12T10:00:00")
        var shelf = Shelf()
        shelf.add(.init(key: .image("digest-a"), kind: .image, date: now.addingTimeInterval(-60), payload: "first"))
        shelf.add(.init(key: .image("digest-b"), kind: .image, date: now.addingTimeInterval(-30), payload: "other"))
        shelf.add(.init(key: .image("digest-a"), kind: .image, date: now, payload: "second"))
        XCTAssertEqual(shelf.items.map(\.payload), ["first", "other"])
    }

    func testAFileAndTextWithTheSameWordsAreDifferentClips() {
        let now = date("2026-11-12T10:00:00")
        var shelf = Shelf()
        shelf.add(text("/tmp/someone/plan.pdf", at: now.addingTimeInterval(-1)))
        shelf.add(file("/tmp/someone/plan.pdf", at: now))
        XCTAssertEqual(shelf.items.count, 2)
    }

    func testOnlyTheNewestFiftyAreKept() {
        let now = date("2026-11-12T10:00:00")
        var shelf = Shelf()
        for index in 0..<55 { shelf.add(text("clip \(index)", at: now.addingTimeInterval(Double(index - 55)))) }
        XCTAssertEqual(shelf.items.count, ClipRules.maximumCount)
        XCTAssertEqual(ClipRules.maximumCount, 50)
        XCTAssertEqual(shelf.items.first?.payload, "clip 54")
        XCTAssertEqual(shelf.items.last?.payload, "clip 5")
    }

    func testRemovingOneOrAll() {
        let now = date("2026-11-12T10:00:00")
        var shelf = Shelf()
        let first = shelf.add(text("one", at: now))
        shelf.add(file("/gone.pdf", at: now))
        shelf.add(text("two", at: now))
        XCTAssertTrue(shelf.remove(id: first.id))
        XCTAssertFalse(shelf.remove(id: first.id))
        XCTAssertTrue(shelf.removeAll { $0.kind == .file })
        XCTAssertFalse(shelf.removeAll { $0.kind == .file })
        XCTAssertEqual(shelf.items.map(\.payload), ["two"])
        shelf.removeAll()
        XCTAssertTrue(shelf.items.isEmpty)
    }

    // MARK: - Memory for copied images

    private let megabyte = 1024 * 1024

    private func image(_ name: String, megabytes: Int, at date: Date) -> Shelf.Item {
        .init(key: .image(name), kind: .image, date: date, payload: name, cost: megabytes * megabyte)
    }

    func testTheBudgetForCopiedImagesIsAHundredMegabytes() {
        XCTAssertEqual(ClipRules.imageBudget, 100 * megabyte)
    }

    func testImagesUpToTheBudgetAreAllKept() {
        let now = date("2026-11-12T10:00:00")
        var shelf = Shelf()
        shelf.add(image("a", megabytes: 40, at: now.addingTimeInterval(-20)))
        shelf.add(image("b", megabytes: 60, at: now.addingTimeInterval(-10)))
        XCTAssertEqual(shelf.items.map(\.payload), ["b", "a"])
        XCTAssertEqual(shelf.imageBytes, 100 * megabyte)
    }

    func testOverTheBudgetTheOldestImagesGoAndNothingElse() {
        let now = date("2026-11-12T10:00:00")
        var shelf = Shelf()
        shelf.add(text("old words", at: now.addingTimeInterval(-60)))
        // A file is not held in memory, so its size neither counts nor makes it go.
        shelf.add(.init(key: .file("/Shots/Recording.mov"), kind: .file, date: now.addingTimeInterval(-55), payload: "/Shots/Recording.mov", cost: 500 * megabyte))
        shelf.add(image("a", megabytes: 50, at: now.addingTimeInterval(-50)))
        shelf.add(text("https://example.com", at: now.addingTimeInterval(-45)))
        shelf.add(image("b", megabytes: 40, at: now.addingTimeInterval(-40)))
        shelf.add(image("c", megabytes: 30, at: now.addingTimeInterval(-30)))
        XCTAssertEqual(shelf.items.map(\.payload), ["c", "b", "https://example.com", "/Shots/Recording.mov", "old words"])
        XCTAssertEqual(shelf.imageBytes, 70 * megabyte)
        // One more can take several older ones with it.
        shelf.add(image("d", megabytes: 90, at: now))
        XCTAssertEqual(shelf.items.map(\.payload), ["d", "https://example.com", "/Shots/Recording.mov", "old words"])
        XCTAssertEqual(shelf.imageBytes, 90 * megabyte)
    }

    func testOneImageOverTheBudgetIsKeptAlone() {
        let now = date("2026-11-12T10:00:00")
        var shelf = Shelf()
        shelf.add(image("small", megabytes: 30, at: now.addingTimeInterval(-30)))
        shelf.add(image("huge", megabytes: 150, at: now.addingTimeInterval(-20)))
        XCTAssertEqual(shelf.items.map(\.payload), ["huge"])
        // Copying words afterwards doesn't make it go: it is still the newest image.
        shelf.add(text("hello", at: now.addingTimeInterval(-10)))
        XCTAssertEqual(shelf.items.map(\.payload), ["hello", "huge"])
        // The next image does.
        shelf.add(image("next", megabytes: 10, at: now))
        XCTAssertEqual(shelf.items.map(\.payload), ["next", "hello"])
    }

    func testARecopiedImageIsNotTakenForTheOldest() {
        let now = date("2026-11-12T10:00:00")
        var shelf = Shelf()
        shelf.add(image("a", megabytes: 60, at: now.addingTimeInterval(-300)))
        shelf.add(image("b", megabytes: 30, at: now.addingTimeInterval(-200)))
        // The same image copied again: no more memory, and it is new again.
        shelf.add(image("a", megabytes: 60, at: now.addingTimeInterval(-100)))
        XCTAssertEqual(shelf.items.map(\.payload), ["a", "b"])
        XCTAssertEqual(shelf.imageBytes, 90 * megabyte)
        shelf.add(image("c", megabytes: 20, at: now))
        XCTAssertEqual(shelf.items.map(\.payload), ["c", "a"])
    }

    // MARK: - Groups by age

    func testTheGroupsForAMorning() {
        let now = date("2026-11-12T10:00:00")
        XCTAssertEqual(ClipAge.of(now, now: now, calendar: calendar), .lastHour)
        XCTAssertEqual(ClipAge.of(date("2026-11-12T09:00:01"), now: now, calendar: calendar), .lastHour)
        XCTAssertEqual(ClipAge.of(date("2026-11-12T09:00:00"), now: now, calendar: calendar), .earlierToday)
        XCTAssertEqual(ClipAge.of(date("2026-11-12T00:00:00"), now: now, calendar: calendar), .earlierToday)
        XCTAssertEqual(ClipAge.of(date("2026-11-11T23:59:59"), now: now, calendar: calendar), .yesterday)
        XCTAssertEqual(ClipAge.of(date("2026-11-11T10:00:01"), now: now, calendar: calendar), .yesterday)
        XCTAssertNil(ClipAge.of(date("2026-11-11T10:00:00"), now: now, calendar: calendar))
        // A clock set back can date a clip a little in the future: it is new.
        XCTAssertEqual(ClipAge.of(now.addingTimeInterval(120), now: now, calendar: calendar), .lastHour)
        XCTAssertEqual(ClipAge.allCases.map(\.title), ["Last hour", "Earlier today", "Yesterday"])
    }

    func testAClipFromJustBeforeMidnightMovesGroupAsTheNightGoesOn() {
        let clip = date("2026-11-11T23:40:00")
        XCTAssertEqual(ClipAge.of(clip, now: date("2026-11-11T23:50:00"), calendar: calendar), .lastHour)
        XCTAssertEqual(ClipAge.of(clip, now: date("2026-11-12T00:10:00"), calendar: calendar), .lastHour)
        XCTAssertEqual(ClipAge.of(clip, now: date("2026-11-12T00:40:00"), calendar: calendar), .yesterday)
        XCTAssertEqual(ClipAge.of(clip, now: date("2026-11-12T23:39:59"), calendar: calendar), .yesterday)
        XCTAssertNil(ClipAge.of(clip, now: date("2026-11-12T23:40:00"), calendar: calendar))
        // Shortly after midnight there is no "earlier today" yet: a clip from 23:00 is yesterday's.
        XCTAssertEqual(ClipAge.of(date("2026-11-11T23:00:00"), now: date("2026-11-12T00:30:00"), calendar: calendar), .yesterday)
    }

    func testSectionsAreNewestFirstAndLeaveOutEmptyGroups() {
        let now = date("2026-11-12T10:00:00")
        var shelf = Shelf()
        shelf.add(text("last night", at: date("2026-11-11T21:00:00")))
        shelf.add(text("a minute ago", at: now.addingTimeInterval(-60)))
        shelf.add(text("ten minutes ago", at: now.addingTimeInterval(-600)))
        let sections = shelf.sections(.all, now: now, calendar: calendar)
        XCTAssertEqual(sections.map(\.age), [.lastHour, .yesterday])
        XCTAssertEqual(sections.map { $0.items.map(\.payload) }, [["a minute ago", "ten minutes ago"], ["last night"]])
    }

    func testSectionsNeverShowAClipThatHasRunOutEvenBeforeItIsPruned() {
        // After a sleep, the pane may draw before the next tick prunes.
        let now = date("2026-11-12T10:00:00")
        var shelf = Shelf()
        shelf.add(text("old", at: now.addingTimeInterval(-25 * hour)))
        shelf.add(text("new", at: now))
        XCTAssertEqual(shelf.sections(.all, now: now, calendar: calendar).flatMap(\.items).map(\.payload), ["new"])
        XCTAssertEqual(shelf.chips(now: now).map(\.count), [1, 1])
    }

    func testChipsShowAllThenEachKindThatHasClipsWithCounts() {
        let now = date("2026-11-12T10:00:00")
        var shelf = Shelf()
        shelf.add(file("/a.pdf", at: now.addingTimeInterval(-5)))
        shelf.add(text("hello", at: now.addingTimeInterval(-4)))
        shelf.add(text("https://example.com", at: now.addingTimeInterval(-3)))
        shelf.add(file("/b.mov", at: now.addingTimeInterval(-2)))
        shelf.add(text("again", at: now.addingTimeInterval(-1)))
        let chips = shelf.chips(now: now)
        XCTAssertEqual(chips.map(\.filter), [.all, .kind(.text), .kind(.link), .kind(.file)])
        XCTAssertEqual(chips.map(\.count), [5, 2, 1, 2])
        XCTAssertEqual(ClipKind.allCases.map(\.title), ["Text", "Links", "Images", "Files"])
        XCTAssertEqual(Shelf().chips(now: now).map(\.count), [0])
    }

    func testAFilterShowsOneKindAndFallsBackToAllWhenThatKindRunsOut() {
        let now = date("2026-11-12T10:00:00")
        var shelf = Shelf()
        let link = shelf.add(text("https://example.com", at: now.addingTimeInterval(-hour * 2)))
        shelf.add(text("hello", at: now))
        let links = shelf.sections(.kind(.link), now: now, calendar: calendar)
        XCTAssertEqual(links.map(\.age), [.earlierToday])
        XCTAssertEqual(links.flatMap(\.items).map(\.payload), ["https://example.com"])
        XCTAssertEqual(shelf.resolved(.kind(.link), now: now), .kind(.link))
        XCTAssertEqual(shelf.resolved(.kind(.image), now: now), .all)
        shelf.remove(id: link.id)
        XCTAssertEqual(shelf.resolved(.kind(.link), now: now), .all)
        XCTAssertEqual(shelf.resolved(.all, now: now), .all)
    }

    // MARK: - Screenshots

    private func shot(_ name: String, _ created: Date, size: Int = 120_000, mark: Bool? = true) -> ScreenshotWatch.File {
        .init(name: name, created: created, size: size, isScreenCapture: mark)
    }

    func testOnlyScreenshotsTakenSinceWatchingStartedCount() {
        let start = date("2026-11-12T10:00:00")
        var watch = ScreenshotWatch(started: start)
        let taken = watch.take([
            shot("Screenshot 2026-11-12 at 09.59.59.png", start.addingTimeInterval(-1)),
            shot("Screenshot 2026-11-12 at 10.00.05.png", start.addingTimeInterval(5)),
        ], now: start.addingTimeInterval(6))
        XCTAssertEqual(taken.map(\.name), ["Screenshot 2026-11-12 at 10.00.05.png"])
    }

    func testNewScreenshotsComeInTheOrderTheyWereTakenWhateverTheListingOrder() {
        let start = date("2026-11-12T10:00:00")
        var watch = ScreenshotWatch(started: start)
        let taken = watch.take([
            shot("c.png", start.addingTimeInterval(30)),
            shot("a.png", start.addingTimeInterval(10)),
            shot("b.png", start.addingTimeInterval(20)),
        ], now: start.addingTimeInterval(31))
        XCTAssertEqual(taken.map(\.name), ["a.png", "b.png", "c.png"])
    }

    func testTwoScreenshotsFromTheSameSecondAreBothTaken() {
        let start = date("2026-11-12T10:00:00")
        var watch = ScreenshotWatch(started: start)
        let moment = start.addingTimeInterval(12)
        XCTAssertEqual(watch.take([shot("Screenshot 2.png", moment)], now: moment).map(\.name), ["Screenshot 2.png"])
        // The second one shows up a tick later with the very same creation time.
        let next = watch.take([shot("Screenshot 2.png", moment), shot("Screenshot 1.png", moment)], now: moment.addingTimeInterval(1))
        XCTAssertEqual(next.map(\.name), ["Screenshot 1.png"])
        XCTAssertEqual(watch.take([shot("Screenshot B.png", moment), shot("Screenshot A.png", moment)], now: moment).map(\.name), ["Screenshot A.png", "Screenshot B.png"])
    }

    func testAScreenshotIsTakenOnlyOnce() {
        let start = date("2026-11-12T10:00:00")
        var watch = ScreenshotWatch(started: start)
        let files = [shot("Screenshot.png", start.addingTimeInterval(3))]
        XCTAssertEqual(watch.take(files, now: start.addingTimeInterval(4)).count, 1)
        XCTAssertEqual(watch.take(files, now: start.addingTimeInterval(5)).count, 0)
        // Still there a day and more later: it is not taken again.
        XCTAssertEqual(watch.take(files, now: start.addingTimeInterval(25 * hour)).count, 0)
    }

    func testHiddenAndTemporaryFilesAreSkipped() {
        let start = date("2026-11-12T10:00:00")
        var watch = ScreenshotWatch(started: start)
        let names = [".Screenshot 2026-11-12 at 10.00.01.png", "~Screenshot.png", "Screenshot.png.tmp", "Screen Recording.mov.part", "Screenshot.png.download"]
        XCTAssertTrue(watch.take(names.map { shot($0, start.addingTimeInterval(1)) }, now: start.addingTimeInterval(2)).isEmpty)
        XCTAssertFalse(watch.isWaiting)
    }

    func testAFileStillBeingWrittenWaitsUntilItHasSomethingInIt() {
        let start = date("2026-11-12T10:00:00")
        var watch = ScreenshotWatch(started: start)
        let created = start.addingTimeInterval(1)
        XCTAssertTrue(watch.take([shot("Screenshot.png", created, size: 0)], now: created).isEmpty)
        XCTAssertTrue(watch.isWaiting, "look again on the next tick even if the folder doesn't change")
        XCTAssertEqual(watch.take([shot("Screenshot.png", created)], now: created.addingTimeInterval(1)).map(\.name), ["Screenshot.png"])
        XCTAssertFalse(watch.isWaiting)
        // An empty file that stays empty is given up on, so the folder isn't read every second for ever.
        XCTAssertTrue(watch.take([shot("Screenshot 9.png", created, size: 0)], now: created.addingTimeInterval(ScreenshotWatch.settleTime + 1)).isEmpty)
        XCTAssertFalse(watch.isWaiting)
    }

    func testTheMarkMacOSWritesRecognisesScreenshotsInAnyLanguage() {
        let start = date("2026-11-12T10:00:00")
        var watch = ScreenshotWatch(started: start)
        let created = start.addingTimeInterval(1)
        let taken = watch.take([
            shot("Bildschirmfoto 2026-11-12 um 10.00.01.png", created, mark: true),
            shot("Capture d’écran 2026-11-12 à 10.00.01.png", created, mark: true),
            shot("Screenshot told it is not one.png", created, mark: false),
            shot("Holiday.png", start.addingTimeInterval(-60 + 120), mark: nil),
        ], now: created.addingTimeInterval(ScreenshotWatch.settleTime + 60))
        XCTAssertEqual(taken.map(\.name), ["Bildschirmfoto 2026-11-12 um 10.00.01.png", "Capture d’écran 2026-11-12 à 10.00.01.png"])
    }

    func testWithoutTheMarkTheEnglishNamesStillCount() {
        let start = date("2026-11-12T10:00:00")
        var watch = ScreenshotWatch(started: start)
        let created = start.addingTimeInterval(1)
        let later = created.addingTimeInterval(ScreenshotWatch.settleTime + 1)
        let taken = watch.take([
            shot("Screenshot 2026-11-12 at 10.00.01.png", created, mark: nil),
            shot("Screen Shot 2026-11-12 at 10.00.01.png", created, mark: nil),
            shot("Screen Recording 2026-11-12 at 10.00.01.mov", created, mark: nil),
            shot("Notes.png", created, mark: nil),
        ], now: later)
        XCTAssertEqual(taken.map(\.name), ["Screen Recording 2026-11-12 at 10.00.01.mov", "Screen Shot 2026-11-12 at 10.00.01.png", "Screenshot 2026-11-12 at 10.00.01.png"])
        XCTAssertFalse(watch.isWaiting)
    }

    func testANewFileWithoutTheMarkYetIsLookedAtAgainForAMoment() {
        // macOS may write its mark a moment after the file appears.
        let start = date("2026-11-12T10:00:00")
        var watch = ScreenshotWatch(started: start)
        let created = start.addingTimeInterval(1)
        XCTAssertTrue(watch.take([shot("Bildschirmfoto.png", created, mark: nil)], now: created).isEmpty)
        XCTAssertTrue(watch.isWaiting)
        XCTAssertEqual(watch.take([shot("Bildschirmfoto.png", created, mark: true)], now: created.addingTimeInterval(1)).map(\.name), ["Bildschirmfoto.png"])
    }

    func testOnlyRecentFilesNeedTheirDetailsRead() {
        let start = date("2026-11-12T10:00:00")
        let watch = ScreenshotWatch(started: start)
        XCTAssertEqual(watch.earliest(now: start.addingTimeInterval(60)), start)
        XCTAssertEqual(watch.earliest(now: start.addingTimeInterval(30 * hour)), start.addingTimeInterval(6 * hour))
    }

    func testTheMarkIsReadFromItsPropertyList() throws {
        // The bytes of the attribute on a real screenshot on this Mac: a binary property list holding true.
        let real = Data([0x62, 0x70, 0x6C, 0x69, 0x73, 0x74, 0x30, 0x30, 0x09, 0x08, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 9])
        XCTAssertEqual(ScreenshotWatch.flag(attribute: real), true)
        let no = try PropertyListSerialization.data(fromPropertyList: false, format: .binary, options: 0)
        XCTAssertEqual(ScreenshotWatch.flag(attribute: no), false)
        let one = try PropertyListSerialization.data(fromPropertyList: 1, format: .binary, options: 0)
        XCTAssertEqual(ScreenshotWatch.flag(attribute: one), true)
        XCTAssertNil(ScreenshotWatch.flag(attribute: nil))
        XCTAssertNil(ScreenshotWatch.flag(attribute: Data("not a plist".utf8)))
        XCTAssertEqual(ScreenshotWatch.attribute, "com.apple.metadata:kMDItemIsScreenCapture")
    }
}
