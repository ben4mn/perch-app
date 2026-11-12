import XCTest
@testable import PerchKit
@testable import PerchUI

#if canImport(AppKit)
import AppKit
#endif

/// How the Display, Reading and Editing settings are saved, reset and handed to the editor.
@MainActor
final class SettingsStoreTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suite = "perch-settings-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    // MARK: Saved Display choices

    func testNothingSavedIsTheStandardDisplay() {
        XCTAssertEqual(DisplaySettings.saved(defaults: defaults), .standard)
    }

    func testSavedDisplayChoicesAreReadBack() {
        defaults.set("extraLarge", forKey: DisplaySettings.Key.interfaceSize)
        defaults.set("compact", forKey: DisplaySettings.Key.density)
        defaults.set(false, forKey: DisplaySettings.Key.taskPreview)
        defaults.set(false, forKey: DisplaySettings.Key.taskChips)
        let display = DisplaySettings.saved(defaults: defaults)
        XCTAssertEqual(display.metrics, DisplayMetrics(size: .extraLarge, density: .compact))
        XCTAssertFalse(display.showsTaskPreview)
        XCTAssertFalse(display.showsTaskChips)
    }

    func testAValueThatIsNotAChoiceReadsAsTheDefault() {
        defaults.set("enormous", forKey: DisplaySettings.Key.interfaceSize)
        defaults.set(3, forKey: DisplaySettings.Key.density)
        defaults.set("perhaps", forKey: DisplaySettings.Key.taskChips)
        XCTAssertEqual(DisplaySettings.saved(defaults: defaults), .standard)
    }

    func testTheZoomShortcutsStepAndStopAtTheEnds() {
        let key = DisplaySettings.Key.interfaceSize
        DisplaySettings.stepSavedInterfaceSize(1, defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: key), "large")
        DisplaySettings.stepSavedInterfaceSize(1, defaults: defaults)
        DisplaySettings.stepSavedInterfaceSize(1, defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: key), "extraLarge")
        DisplaySettings.stepSavedInterfaceSize(0, defaults: defaults)
        XCTAssertNil(defaults.object(forKey: key), "Default is saved as nothing at all")
        for _ in 0..<5 { DisplaySettings.stepSavedInterfaceSize(-1, defaults: defaults) }
        XCTAssertEqual(defaults.string(forKey: key), "small")
        DisplaySettings.stepSavedInterfaceSize(1, defaults: defaults)
        XCTAssertNil(defaults.object(forKey: key))
    }

    // MARK: Reset

    func testEachGroupResetsOnlyItsOwnKeys() {
        let groups = [DisplaySettings.Key.all, ReadingSettings.Key.all, EditingSettings.Key.all]
        let theme = [ThemeStore.Keys.selected, ThemeStore.Keys.appearance, ThemeStore.Keys.accent, ThemeStore.Keys.overrides, ThemeStore.Keys.imported]
        // Things that are neither Display, Reading nor Editing choices and must outlive every reset.
        let others = theme + [ReadingSettings.Key.splitFraction, "notchEnabled", "calendarMode", "folderLayout"]
        for (index, keys) in groups.enumerated() {
            XCTAssertEqual(Set(keys).count, keys.count, "a key is listed twice")
            XCTAssertTrue(Set(keys).isDisjoint(with: others))
            for other in groups[(index + 1)...] { XCTAssertTrue(Set(keys).isDisjoint(with: other), "two groups share a key") }
        }
        for keys in groups {
            for key in groups.flatMap({ $0 }) + others { defaults.set("kept", forKey: key) }
            SettingsReset.remove(keys, from: defaults)
            for key in keys { XCTAssertNil(defaults.object(forKey: key), "\(key) should be gone") }
            for key in groups.flatMap({ $0 }) + others where !keys.contains(key) {
                XCTAssertEqual(defaults.string(forKey: key), "kept", "\(key) belongs to something else")
            }
        }
    }

    // MARK: Editor line width

    func testEveryLineWidthIsARealStepForEveryEditorFont() {
        for mono in [true, false] {
            let narrow = EditingSettings.characters(.narrow, mono: mono) ?? 0
            let medium = EditingSettings.characters(.medium, mono: mono) ?? 0
            let wide = EditingSettings.characters(.wide, mono: mono) ?? 0
            XCTAssertLessThan(narrow, medium)
            XCTAssertLessThan(medium, wide)
            XCTAssertNil(EditingSettings.characters(.full, mono: mono))
        }
        // The default is what the editor had before the setting existed: 80 in Mono, the reader's 68 otherwise.
        XCTAssertEqual(EditingSettings.characters(.medium, mono: true), 80)
        XCTAssertEqual(EditingSettings.characters(.medium, mono: false), 68)
    }

    // MARK: What the editor may change as you type

    func testTheEditorShipsWithNothingThatRewritesTyping() {
        let behavior = EditorBehavior()
        XCTAssertFalse(behavior.smartPunctuation)
        XCTAssertEqual(behavior.typing, .standard)
        XCTAssertEqual(MarkdownEditing.Options.standard.indent.unit, MarkdownEditing.indentUnit)
    }

    #if os(macOS)
    func testTheMacTextViewNeverSubstitutesUnlessAsked() {
        let view = PerchTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        // A new text view follows the Mac's keyboard settings, which usually have all of these on.
        view.isAutomaticQuoteSubstitutionEnabled = true
        view.isAutomaticDashSubstitutionEnabled = true
        view.isAutomaticTextReplacementEnabled = true
        view.isAutomaticLinkDetectionEnabled = true
        view.isContinuousSpellCheckingEnabled = true

        view.apply(EditorBehavior())
        XCTAssertFalse(view.isAutomaticQuoteSubstitutionEnabled)
        XCTAssertFalse(view.isAutomaticDashSubstitutionEnabled)
        XCTAssertFalse(view.isAutomaticTextReplacementEnabled)
        XCTAssertFalse(view.isAutomaticLinkDetectionEnabled)
        XCTAssertFalse(view.isAutomaticDataDetectionEnabled)
        XCTAssertFalse(view.isContinuousSpellCheckingEnabled, "the Mac editor has never underlined spelling by default")
        XCTAssertEqual(view.isAutomaticSpellingCorrectionEnabled, NSSpellChecker.isAutomaticSpellingCorrectionEnabled, "autocorrect follows the Mac")

        var asked = EditorBehavior()
        asked.smartPunctuation = true
        asked.spellCheck = true
        asked.autocorrect = false
        view.apply(asked)
        XCTAssertTrue(view.isAutomaticQuoteSubstitutionEnabled)
        XCTAssertTrue(view.isAutomaticDashSubstitutionEnabled)
        XCTAssertTrue(view.isContinuousSpellCheckingEnabled)
        XCTAssertFalse(view.isAutomaticSpellingCorrectionEnabled)
        // Text replacement and link detection have no setting: they stay off.
        XCTAssertFalse(view.isAutomaticTextReplacementEnabled)
        XCTAssertFalse(view.isAutomaticLinkDetectionEnabled)

        view.apply(EditorBehavior())
        XCTAssertFalse(view.isAutomaticQuoteSubstitutionEnabled)
        XCTAssertFalse(view.isAutomaticDashSubstitutionEnabled)
    }

    func testChangingATextCheckingSettingNeverChangesTheText() {
        let text = "\"quoted\" -- dashes... (c) teh http://example.com 'single'\n- [ ] it's\n"
        let view = PerchTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        view.string = text
        for smart in [true, false, true] {
            for spelling in [true, false] {
                var behavior = EditorBehavior()
                behavior.smartPunctuation = smart
                behavior.spellCheck = spelling
                behavior.autocorrect = spelling
                behavior.typing = .init(continuesLists: !smart, tabIndentsLists: spelling, wrapsSelection: smart, indent: smart ? .tab : .twoSpaces)
                view.apply(behavior)
                XCTAssertEqual(view.string, text)
            }
        }
    }
    #endif
}
