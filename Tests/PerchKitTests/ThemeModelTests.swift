import XCTest
@testable import PerchKit

final class ThemeModelTests: XCTestCase {
    func testHexParsingAndFormatting() {
        XCTAssertEqual(ThemeRGB(hex: "#FF8A4C")?.hex, "#FF8A4C")
        XCTAssertEqual(ThemeRGB(hex: "ff8a4c")?.hex, "#FF8A4C")
        XCTAssertEqual(ThemeRGB(hex: " #fa0 ")?.hex, "#FFAA00")
        XCTAssertEqual(ThemeRGB(hex: "#11223380")?.hex, "#11223380")
        XCTAssertEqual(ThemeRGB(hex: "#112233FF")?.hex, "#112233")
        XCTAssertEqual(ThemeRGB(hex: "#000000")?.red, 0)
        XCTAssertEqual(ThemeRGB(hex: "#FFFFFF")?.blue, 1)
        for bad in ["", "#", "#12", "#12345", "#GGGGGG", "red", "#1234567", "#１２３４５６"] {
            XCTAssertNil(ThemeRGB(hex: bad), bad)
        }
    }

    func testContrastRatio() throws {
        XCTAssertEqual(try XCTUnwrap(ThemeContrast.ratio("#000000", "#FFFFFF")), 21, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(ThemeContrast.ratio("#FFFFFF", "#000000")), 21, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(ThemeContrast.ratio("#336699", "#336699")), 1, accuracy: 0.001)
        // A well-known reference pair: #767676 is the lightest grey that passes AA on white.
        XCTAssertEqual(try XCTUnwrap(ThemeContrast.ratio("#767676", "#FFFFFF")), 4.54, accuracy: 0.01)
        XCTAssertNil(ThemeContrast.ratio("nope", "#FFFFFF"))
        XCTAssertEqual(ThemeContrast.readableText(on: "#FFFFFF"), "#17131F")
        XCTAssertEqual(ThemeContrast.readableText(on: "#101010"), "#FFFFFF")
    }

    func testEveryPresetParses() {
        XCTAssertGreaterThanOrEqual(ThemePresets.light.count, 4)
        XCTAssertGreaterThanOrEqual(ThemePresets.dark.count, 14)
        for theme in ThemePresets.all {
            for key in ThemeColorKey.allCases {
                XCTAssertNotNil(ThemeRGB(hex: theme[key]), "\(theme.id).\(key.rawValue) = \(theme[key])")
            }
            XCTAssertFalse(theme.name.isEmpty)
        }
    }

    func testPresetIDsAndNamesAreUnique() {
        let ids = ThemePresets.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertFalse(ids.contains(ThemePresets.systemID))
        XCTAssertEqual(Set(ThemePresets.all.map(\.name)).count, ids.count)
    }

    func testPresetsAreSortedIntoLightAndDark() throws {
        for theme in ThemePresets.light {
            XCTAssertFalse(theme.isDark, theme.id)
            XCTAssertGreaterThan(try XCTUnwrap(ThemeRGB(hex: theme.background)).luminance, 0.5, theme.id)
        }
        for theme in ThemePresets.dark {
            XCTAssertTrue(theme.isDark, theme.id)
            XCTAssertLessThan(try XCTUnwrap(ThemeRGB(hex: theme.background)).luminance, 0.2, theme.id)
        }
    }

    func testEveryPresetMeetsContrastThresholds() throws {
        var failures: [String] = []
        for theme in ThemePresets.all {
            // The brief's floor, stated directly: AA for text, 3:1 for muted text.
            let text = try XCTUnwrap(ThemeContrast.ratio(theme.text, theme.background))
            let muted = try XCTUnwrap(ThemeContrast.ratio(theme.textMuted, theme.background))
            if text < 4.5 { failures.append("\(theme.id): text on background \(text)") }
            if muted < 3 { failures.append("\(theme.id): textMuted on background \(muted)") }
            // And the fuller set of pairs the settings screen warns about.
            for issue in theme.contrastIssues {
                failures.append(String(format: "%@: %@ on %@ %.2f < %.1f", theme.id, issue.foreground.rawValue, issue.background.rawValue, issue.ratio, issue.required))
            }
        }
        XCTAssertTrue(failures.isEmpty, "\n" + failures.joined(separator: "\n"))
    }

    func testContrastIssuesAreReported() {
        var theme = ThemePresets.perchDark
        theme.text = theme.background
        let issues = theme.contrastIssues(for: .text)
        XCTAssertTrue(issues.contains { $0.foreground == .text && $0.background == .background && $0.ratio < 1.01 })
        XCTAssertTrue(theme.contrastIssues(for: .background).contains { $0.foreground == .text })
        XCTAssertTrue(issues[0].message.contains("4.5:1"))
    }

    func testExportImportRoundTrips() throws {
        for theme in ThemePresets.all {
            let json = theme.exportedJSON()
            XCTAssertEqual(try ThemePalette(json: json), theme, theme.id)
        }
        var custom = ThemePresets.preset(id: "nord")!
        custom.accent = "#FF00AA"
        custom.name = "My Nord"
        XCTAssertEqual(try ThemePalette(json: custom.exportedJSON()), custom)
    }

    func testImportToleratesUnknownMissingAndBadValues() throws {
        let json = """
        { "format": "perch-theme", "version": 99, "name": "Half", "isDark": false, "futureThing": [1, 2, {"a": null}],
          "colors": { "background": "#fff", "accent": "#0000ff", "text": "not a colour", "glow": "#123456", "border": 7 } }
        """
        let theme = try ThemePalette(json: json)
        XCTAssertEqual(theme.name, "Half")
        XCTAssertEqual(theme.id, "custom-half")
        XCTAssertFalse(theme.isDark)
        XCTAssertEqual(theme.background, "#FFFFFF")
        XCTAssertEqual(theme.accent, "#0000FF")
        XCTAssertEqual(theme.accentText, "#FFFFFF")
        XCTAssertEqual(theme.text, ThemePresets.perchLight.text)
        XCTAssertEqual(theme.border, ThemePresets.perchLight.border)

        // Flat colours, and light or dark guessed from the background.
        let flat = try ThemePalette(json: ##"{"background":"#101014","text":"#eeeeee"}"##)
        XCTAssertTrue(flat.isDark)
        XCTAssertEqual(flat.surface, ThemePresets.perchDark.surface)
        XCTAssertEqual(flat.name, "Imported theme")

        XCTAssertThrowsError(try ThemePalette(json: "hello"))
        XCTAssertThrowsError(try ThemePalette(json: "[]"))
        XCTAssertThrowsError(try ThemePalette(json: #"{"name":"Empty","colors":{}}"#))
    }

    func testSystemFollowsDeviceAndAppearance() {
        var settings = ThemeSettings()
        XCTAssertEqual(settings.selectedID, ThemePresets.systemID)
        XCTAssertNil(settings.forcedDark)
        XCTAssertEqual(settings.palette(systemIsDark: false), ThemePresets.perchLight)
        XCTAssertEqual(settings.palette(systemIsDark: true), ThemePresets.perchDark)
        XCTAssertFalse(settings.isCustomised(systemIsDark: true))

        settings.appearance = .light
        XCTAssertEqual(settings.forcedDark, false)
        XCTAssertEqual(settings.palette(systemIsDark: true), ThemePresets.perchLight)
        settings.appearance = .dark
        XCTAssertEqual(settings.palette(systemIsDark: false), ThemePresets.perchDark)

        // A named theme wins over both the device and the System appearance.
        settings.selectedID = "paper"
        XCTAssertEqual(settings.forcedDark, false)
        XCTAssertEqual(settings.palette(systemIsDark: true).id, "paper")

        // An id that no longer exists behaves like System.
        settings.selectedID = "gone"
        settings.appearance = .auto
        XCTAssertNil(settings.forcedDark)
        XCTAssertEqual(settings.palette(systemIsDark: true), ThemePresets.perchDark)
    }

    func testOverridesMergeAndReset() {
        var settings = ThemeSettings(selectedID: "nord")
        let nord = ThemePresets.preset(id: "nord")!
        settings.setColor(.background, to: "#101010", systemIsDark: false)
        settings.setColor(.text, to: "bogus", systemIsDark: false)
        XCTAssertEqual(settings.overrides, ["nord": ["background": "#101010"]])
        var expected = nord
        expected.background = "#101010"
        XCTAssertEqual(settings.palette(systemIsDark: false), expected)
        XCTAssertTrue(settings.isCustomised(systemIsDark: false))
        XCTAssertTrue(settings.isOverridden(.background, systemIsDark: false))
        XCTAssertFalse(settings.isOverridden(.text, systemIsDark: false))

        // Another theme is untouched by Nord's changes.
        settings.selectedID = "dracula"
        XCTAssertEqual(settings.palette(systemIsDark: false), ThemePresets.preset(id: "dracula")!)
        settings.selectedID = "nord"

        // Putting the shipped colour back clears the change.
        settings.setColor(.background, to: nord.background.lowercased(), systemIsDark: false)
        XCTAssertTrue(settings.overrides.isEmpty)

        // The quick accent applies to any theme and picks readable text; a per-colour change still wins.
        settings.accent = "#102030"
        XCTAssertEqual(settings.palette(systemIsDark: false).accent, "#102030")
        XCTAssertEqual(settings.palette(systemIsDark: false).accentText, "#FFFFFF")
        settings.setColor(.accent, to: "#ABCDEF", systemIsDark: false)
        XCTAssertEqual(settings.palette(systemIsDark: false).accent, "#ABCDEF")
        settings.selectedID = "gruvbox"
        XCTAssertEqual(settings.palette(systemIsDark: false).accent, "#102030")

        settings.selectedID = "nord"
        settings.resetCustomisation()
        XCTAssertEqual(settings.palette(systemIsDark: false), nord)
        XCTAssertFalse(settings.isCustomised(systemIsDark: false))
    }

    func testSystemOverridesAreKeptPerHalf() {
        var settings = ThemeSettings()
        settings.setColor(.accent, to: "#00AA88", systemIsDark: true)
        XCTAssertEqual(settings.palette(systemIsDark: true).accent, "#00AA88")
        XCTAssertEqual(settings.palette(systemIsDark: false), ThemePresets.perchLight)
        settings.resetCustomisation()
        XCTAssertEqual(settings.palette(systemIsDark: true), ThemePresets.perchDark)
    }

    func testImportingIntoSettings() throws {
        // A customised preset travels as that preset plus its changes.
        var mac = ThemeSettings(selectedID: "tokyo-night")
        mac.setColor(.surface, to: "#2A2F45", systemIsDark: false)
        mac.accent = "#FF8A4C"
        let json = mac.exportedJSON(systemIsDark: false)

        var phone = ThemeSettings()
        let shown = try phone.importTheme(json: json)
        XCTAssertEqual(phone.selectedID, "tokyo-night")
        XCTAssertEqual(shown, mac.palette(systemIsDark: false))
        XCTAssertEqual(phone.palette(systemIsDark: true), mac.palette(systemIsDark: false))
        XCTAssertEqual(phone.overrides["tokyo-night"]?["surface"], "#2A2F45")

        // An unknown theme is kept as an imported one, and replaced if pasted again.
        let foreign = ##"{"id":"sunset","name":"Sunset","isDark":true,"colors":{"background":"#201018","accent":"#ff9966"}}"##
        try phone.importTheme(json: foreign)
        try phone.importTheme(json: foreign)
        XCTAssertEqual(phone.imported.map(\.id), ["sunset"])
        XCTAssertEqual(phone.selectedID, "sunset")
        XCTAssertEqual(phone.palette(systemIsDark: false).background, "#201018")
        XCTAssertEqual(phone.forcedDark, true)
        phone.removeImported(id: "sunset")
        XCTAssertEqual(phone.selectedID, ThemePresets.systemID)

        XCTAssertThrowsError(try phone.importTheme(json: "not json")) { XCTAssertEqual($0 as? ThemeImportError, .notATheme) }

        // Perch's own dark theme, pasted while on System, stays System and pins dark.
        var fresh = ThemeSettings()
        try fresh.importTheme(json: ThemePresets.perchDark.exportedJSON())
        XCTAssertEqual(fresh.selectedID, ThemePresets.systemID)
        XCTAssertEqual(fresh.appearance, .dark)
        XCTAssertTrue(fresh.overrides.isEmpty)
    }

    func testQuickAccentUsesTheShadeThatSuitsTheTheme() throws {
        // Picked in the dark, a named accent switches to its light shade on a light theme, and back.
        var settings = ThemeSettings()
        settings.setAccent("#6CA8FF")
        XCTAssertEqual(settings.palette(systemIsDark: true).accent, "#6CA8FF")
        XCTAssertEqual(settings.palette(systemIsDark: false).accent, "#1F6FE0")
        settings.selectedID = "paper"
        XCTAssertEqual(settings.palette(systemIsDark: true).accent, "#1F6FE0")
        XCTAssertEqual(settings.palette(systemIsDark: true).accentText, "#FFFFFF")
        // A colour of the user's own is used as it is.
        settings.setAccent("#123456")
        XCTAssertEqual(settings.palette(systemIsDark: true).accent, "#123456")
        settings.setAccent("nonsense")
        XCTAssertNil(settings.accent)

        // Every named accent can be told from the page in every built-in theme.
        for theme in ThemePresets.all {
            for choice in ThemePresets.accentChoices {
                let shade = ThemePresets.accent(choice.dark, isDark: theme.isDark)
                XCTAssertEqual(shade, theme.isDark ? choice.dark : choice.light)
                XCTAssertGreaterThanOrEqual(try XCTUnwrap(ThemeContrast.ratio(shade, theme.background)), ThemeContrast.large, "\(choice.name) on \(theme.id)")
            }
        }
    }

    func testQuickAccentReplacesOnlyTheShowingThemesAccent() {
        var settings = ThemeSettings(selectedID: "nord")
        settings.setColor(.accent, to: "#ABCDEF", systemIsDark: true)
        settings.setColor(.surface, to: "#404858", systemIsDark: true)
        settings.selectedID = ThemePresets.systemID
        settings.setColor(.accent, to: "#00AA88", systemIsDark: true)
        settings.setColor(.accentText, to: "#000000", systemIsDark: false)

        settings.setAccent("#C2376B")
        XCTAssertNil(settings.overrides[ThemePresets.perchDark.id])
        XCTAssertNil(settings.overrides[ThemePresets.perchLight.id])
        // Nord wasn't showing, so its hand-picked accent stays and still wins there.
        XCTAssertEqual(settings.overrides["nord"], ["accent": "#ABCDEF", "surface": "#404858"])
        settings.selectedID = "nord"
        XCTAssertEqual(settings.palette(systemIsDark: true).accent, "#ABCDEF")
        settings.setAccent(nil)
        XCTAssertEqual(settings.overrides["nord"], ["surface": "#404858"])

        // Putting a colour back to the quick accent's shade clears the change rather than storing it.
        settings.setAccent("#C2376B")
        settings.setColor(.accent, to: "#FF7EA8", systemIsDark: true)
        XCTAssertNil(settings.overrides["nord"]?["accent"])
    }

    func testSavedSettingsKeepWhatIsUsable() {
        XCTAssertEqual(ThemeSettings.overrides(savedJSON: "not json"), [:])
        XCTAssertEqual(ThemeSettings.overrides(savedJSON: "[1, 2]"), [:])
        let overrides = ThemeSettings.overrides(savedJSON: ##"{"nord":{"accent":"#abc","glow":"#123456","text":"blue","border":7},"paper":"x","gruvbox":{"text":null}}"##)
        XCTAssertEqual(overrides, ["nord": ["accent": "#AABBCC"]])

        XCTAssertEqual(ThemeSettings.importedThemes(savedJSON: "{}"), [])
        XCTAssertEqual(ThemeSettings.importedThemes(savedJSON: ""), [])
        let saved = ##"""
        [ {"id":"sunset","name":"First","colors":{"background":"#201018"}}, 42, {"id":"empty","colors":{}}, "text",
          {"id":"nord","name":"Fake Nord","colors":{"background":"#ffffff"}}, {"id":"system","colors":{"background":"#ffffff"}},
          {"id":"dawn","colors":{"background":"#fff"}}, {"id":"sunset","name":"Second","colors":{"background":"#301018"}} ]
        """##
        let themes = ThemeSettings.importedThemes(savedJSON: saved)
        XCTAssertEqual(themes.map(\.id), ["dawn", "sunset"])
        XCTAssertEqual(themes.last?.name, "Second")
        // What is written is read back unchanged.
        let data = try! JSONEncoder().encode(themes)
        XCTAssertEqual(ThemeSettings.importedThemes(savedJSON: String(decoding: data, as: UTF8.self)), themes)
    }

    func testImportingHostileInput() throws {
        var settings = ThemeSettings(selectedID: "dracula")
        settings.setColor(.text, to: "#FFFFFF", systemIsDark: true)
        let before = settings
        let bad = [
            "", "null", "[]", "{}", "42", ##"{"colors":"#ffffff"}"##, ##"{"colors":{"background":12}}"##, ##"{"background":"#12"}"##,
            ##"{"name":"x","isDark":"yes"}"##, String(repeating: "[", count: 5000),
            ##"{"name":""## + String(repeating: "a", count: ThemeSettings.importSizeLimit) + ##"","background":"#000000"}"##,
        ]
        for json in bad {
            XCTAssertThrowsError(try settings.importTheme(json: json), String(json.prefix(40)))
            XCTAssertEqual(settings, before, String(json.prefix(40)))
        }

        // Wrong types beside one good colour: the good colour is taken, the rest fall back.
        let odd = try settings.importTheme(json: ##"{"id":7,"name":["a"],"isDark":"yes","colors":{"background":"#FFFFFF","text":"#12345"}}"##)
        XCTAssertEqual(odd.id, "custom-imported-theme")
        XCTAssertFalse(odd.isDark)
        XCTAssertEqual(odd.text, ThemePresets.perchLight.text)

        // Long names and ids are cut; an id of "system" can't shadow the System choice.
        let long = try settings.importTheme(json: ##"{"id":""## + String(repeating: "i", count: 500) + ##"","name":""## + String(repeating: "n", count: 500) + ##"","background":"#000"}"##)
        XCTAssertEqual(long.id.count, 80)
        XCTAssertEqual(long.name.count, 60)
        let system = try settings.importTheme(json: ##"{"id":"system","background":"#000"}"##)
        XCTAssertEqual(system.id, "custom-system")
        XCTAssertEqual(settings.selectedID, "custom-system")
        XCTAssertFalse(settings.followsSystem)

        // A preset's id never becomes an imported theme: it is that preset with its colours changed.
        let count = settings.imported.count
        try settings.importTheme(json: ##"{"id":"nord","name":"Evil","isDark":false,"colors":{"background":"#111111"}}"##)
        XCTAssertEqual(settings.imported.count, count)
        XCTAssertEqual(settings.palette(systemIsDark: false).name, "Nord")
        XCTAssertEqual(settings.palette(systemIsDark: false).background, "#111111")
        XCTAssertEqual(settings.forcedDark, true)
        // Removing by a preset's id does nothing.
        settings.removeImported(id: "nord")
        XCTAssertEqual(settings.selectedID, "nord")
        XCTAssertNotNil(settings.overrides["nord"])

        // The list of imported themes can't grow without end, and dropped themes take their changes with them.
        var crowded = ThemeSettings()
        try crowded.importTheme(json: ##"{"id":"first","background":"#000"}"##)
        crowded.setColor(.text, to: "#FFFFFF", systemIsDark: true)
        for index in 0..<ThemeSettings.importedLimit { try crowded.importTheme(json: ##"{"id":"t\##(index)","background":"#000"}"##) }
        XCTAssertEqual(crowded.imported.count, ThemeSettings.importedLimit)
        XCTAssertNil(crowded.palette(id: "first"))
        XCTAssertNil(crowded.overrides["first"])
    }

    func testCSSVariables() {
        let theme = ThemePresets.perchDark
        let css = theme.cssVariables
        XCTAssertEqual(css["--perch-bg"], theme.background)
        XCTAssertEqual(css["--perch-text"], theme.text)
        XCTAssertEqual(css["--perch-muted"], theme.textMuted)
        XCTAssertEqual(css["--perch-accent"], theme.accent)
        XCTAssertEqual(css["--perch-surface"], theme.surface)
        XCTAssertEqual(css["--perch-border"], theme.border)
        XCTAssertEqual(css["colorScheme"], "dark")
        XCTAssertEqual(ThemePresets.perchLight.cssVariables["colorScheme"], "light")
        XCTAssertNotNil(ThemeRGB(hex: css["--perch-code-bg"] ?? ""))
        XCTAssertTrue(theme.cssDeclarations.contains("--perch-accent: #FF8A4C;"))
        XCTAssertTrue(theme.cssDeclarations.hasSuffix("color-scheme: dark;"))
        // Text stays readable on the derived code background in every preset.
        for preset in ThemePresets.all {
            XCTAssertGreaterThanOrEqual(ThemeContrast.ratio(preset.text, preset.codeBackground) ?? 0, 4.5, preset.id)
        }
    }
}
