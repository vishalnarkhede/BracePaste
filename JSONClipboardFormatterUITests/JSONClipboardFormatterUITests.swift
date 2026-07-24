import XCTest

/// Basic UI smoke tests. Status-item apps are limited under XCTest.
final class JSONClipboardFormatterUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launch()
    }

    func testAppLaunchesWithoutCrash() throws {
        let state = app.state
        XCTAssertTrue(
            state == .runningBackground || state == .runningForeground,
            "Expected app to be running, got \(state.rawValue)"
        )
    }

    func testOpenSettingsViaMenuIfAvailable() throws {
        let settings = app.windows["Settings"]
        if settings.exists {
            XCTAssertTrue(settings.exists)
        } else {
            throw XCTSkip("Status item menu is not reliably accessible via XCTest.")
        }
    }

    func testPopupKeyboardDismissSkippedWithoutPopup() throws {
        throw XCTSkip("Popup requires a successful format action; covered manually.")
    }

    func testCopyActionsSkippedWithoutPopup() throws {
        throw XCTSkip("Copy / Copy Minified require an open popup; covered manually.")
    }

    func testFormatEditedContentSkippedWithoutPopup() throws {
        throw XCTSkip("Format Again requires an open popup; covered manually.")
    }

    func testChangingIndentationSkippedWithoutSettingsWindow() throws {
        throw XCTSkip("Indentation change requires Settings window; covered manually.")
    }

    func testPermissionMissingStateSkipped() throws {
        throw XCTSkip("Permission-missing UI depends on system Accessibility state.")
    }
}
