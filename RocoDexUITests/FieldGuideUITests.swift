import XCTest

@MainActor
final class FieldGuideUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["扫描精灵"].firstMatch.waitForExistence(timeout: 10))
    }

    private func openKeypad() {
        let key = app.buttons["数字 0"]
        if !key.exists { app.buttons["查编号"].tap() }
        XCTAssertTrue(key.waitForExistence(timeout: 3))
    }

    private func enter(_ number: String) {
        openKeypad()
        for character in number { app.buttons["数字 " + String(character)].tap() }
    }

    private func lookup(_ number: String) {
        enter(number)
        app.buttons["按编号查找"].tap()
        XCTAssertTrue(app.staticTexts["NO. " + number].firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["查看特性和完整档案"].waitForExistence(timeout: 3))
    }

    func testInlineArtworkCanToggleAndPersists() throws {
        lookup("008")
        let toggle = app.buttons["portraitMediaToggle"]
        let animation = app.descendants(matching: .any).matching(identifier: "animationViewport").firstMatch
        let still = app.images["staticPortrait"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if toggle.value as? String == "静图" { toggle.tap() }
        XCTAssertTrue(animation.waitForExistence(timeout: 8))
        let firstFrame = try XCTUnwrap(animation.value as? String)
        let moves = NSPredicate { _, _ in
            guard let value = animation.value as? String else { return false }
            return value != firstFrame
        }
        let wait = XCTNSPredicateExpectation(predicate: moves, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [wait], timeout: 5), .completed)
        XCTAssertTrue(app.buttons["portraitNarration"].isHittable)
        XCTAssertTrue(app.staticTexts["水蓝蓝"].firstMatch.exists)
        toggle.tap()
        XCTAssertTrue(still.waitForExistence(timeout: 5))
        XCTAssertFalse(animation.exists)
        XCTAssertEqual(toggle.value as? String, "静图")

        app.terminate()
        app.launch()
        XCTAssertTrue(still.waitForExistence(timeout: 8))
        XCTAssertEqual(toggle.value as? String, "静图")
        toggle.tap()
        XCTAssertTrue(animation.waitForExistence(timeout: 5))
        lookup("005")
        XCTAssertTrue(still.waitForExistence(timeout: 5))
        XCTAssertFalse(toggle.exists)
        XCTAssertFalse(animation.exists)
        XCTAssertTrue(app.buttons["portraitNarration"].isHittable)
    }

    func testNarrationCanBePlayedAndStoppedInPortraitAndDetails() {
        lookup("008")
        let play = app.buttons["portraitNarration"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        XCTAssertTrue(app.buttons["停止介绍"].firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        play.tap()
        XCTAssertTrue(app.buttons["播放介绍"].firstMatch.waitForExistence(timeout: 5))
        lookup("005")
        app.buttons["查看特性和完整档案"].tap()
        app.buttons["detailNarration"].tap()
        XCTAssertTrue(app.buttons["停止介绍"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        XCTAssertEqual(play.label, "播放介绍")
    }

    func testNumberLookupSkillsAndEvolution() {
        lookup("002")
        XCTAssertTrue(app.staticTexts["喵喵"].firstMatch.exists)
        app.buttons["向右"].tap()
        XCTAssertTrue(app.staticTexts["技能"].waitForExistence(timeout: 3))
        app.buttons["向右"].tap()
        XCTAssertTrue(app.staticTexts["进化"].waitForExistence(timeout: 3))
        let middle = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "喵呜")).firstMatch
        XCTAssertTrue(middle.waitForExistence(timeout: 3))
        middle.tap()
        XCTAssertTrue(app.staticTexts["NO. 003"].firstMatch.waitForExistence(timeout: 3))
        app.buttons["向右"].tap()
        XCTAssertTrue(app.staticTexts["档案"].exists)
        XCTAssertTrue(app.staticTexts["喵呜"].firstMatch.exists)
    }

    func testSharedNumberOpensDistinctFormsAndHighNumberSearch() {
        lookup("001")
        XCTAssertTrue(app.staticTexts["迪莫"].firstMatch.exists)
        app.buttons["chooseForm"].tap()
        let variant = app.buttons["entry-10558"]
        XCTAssertTrue(variant.waitForExistence(timeout: 5))
        variant.tap()
        XCTAssertTrue(variant.waitForNonExistence(timeout: 5),app.debugDescription)
        XCTAssertTrue(app.staticTexts["圣光迪莫"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["NO. 001"].firstMatch.exists)
        XCTAssertFalse(app.buttons["portraitMediaToggle"].exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["圣光迪莫"].firstMatch.waitForExistence(timeout: 5))

        openKeypad()
        app.buttons["按编号查找"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("496")
        let result = app.buttons["entry-496"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertTrue(app.staticTexts["铃兰夫人"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["NO. 496"].firstMatch.exists)
        XCTAssertFalse(app.buttons["portraitMediaToggle"].exists)
    }

    func testInvalidNumberCanBeCorrectedOrCancelled() {
        lookup("008")
        enter("999")
        app.buttons["按编号查找"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "重新输入编号")).firstMatch.waitForExistence(timeout: 3))
        app.buttons["退一位"].tap()
        XCTAssertTrue(app.staticTexts["NO. 99"].exists)
        app.buttons["取消当前操作"].tap()
        XCTAssertTrue(app.staticTexts["NO. 008"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["水蓝蓝"].firstMatch.exists)
        openKeypad()
        app.buttons["按编号查找"].tap()
        XCTAssertTrue(app.navigationBars["精灵名册"].waitForExistence(timeout: 3))
        app.buttons["完成"].tap()
    }

    func testScannerAllowsOpeningAndDismissingPhotoLibrary() {
        lookup("008")
        app.buttons["扫描精灵"].firstMatch.tap()
        let photo = app.buttons["从相册识别"]
        XCTAssertTrue(photo.waitForExistence(timeout: 8))
        photo.tap()
        // PHPicker is a system service embedded in the app's accessibility tree.
        let close = app.buttons.matching(NSPredicate(format:
            "label IN %@ OR identifier IN %@", ["取消", "Cancel", "关闭", "Close"], ["Cancel", "Close"])).firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 8), app.debugDescription)
        close.tap()
        XCTAssertTrue(photo.waitForExistence(timeout: 4))
        if app.buttons["取消当前操作"].exists { app.buttons["取消当前操作"].tap() }
    }

    private func importMostRecentPhoto() {
        app.buttons["扫描精灵"].firstMatch.tap()
        let photo = app.buttons["从相册识别"]
        XCTAssertTrue(photo.waitForExistence(timeout: 8))
        photo.tap()
        let modernAsset = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        let legacyAsset = app.cells.matching(NSPredicate(format:
            "identifier BEGINSWITH %@ OR label CONTAINS %@ OR label CONTAINS[c] %@",
            "Grid View Asset", "照片", "Photo")).firstMatch
        let assetsLoaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            modernAsset.exists || legacyAsset.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [assetsLoaded], timeout: 20), .completed, app.debugDescription)
        (modernAsset.exists ? modernAsset : legacyAsset).tap()
    }

    /// Run on a dedicated Simulator after adding Art/008.png as its newest photo
    /// and setting TEST_RUNNER_ROCO_TEST_PHOTO=1 on the xcodebuild invocation.
    func testImportedWaterBluePhotoOpensDiscoveredEntry() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ROCO_TEST_PHOTO"] == "1",
                          "Seed a dedicated Simulator with Art/008.png to exercise PHPicker import.")
        lookup("002")
        importMostRecentPhoto()
        XCTAssertTrue(app.staticTexts["已发现"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.staticTexts["NO. 008"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["水蓝蓝"].firstMatch.exists)
    }

    /// Seed a dedicated Simulator with Art/496.png as the newest photo.
    func testImportedLateCatalogEntryCanBeDiscovered() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ROCO_TEST_496_PHOTO"] == "1")
        lookup("008")
        importMostRecentPhoto()
        XCTAssertTrue(app.staticTexts["铃兰夫人"].firstMatch.waitForExistence(timeout: 20),app.debugDescription)
        XCTAssertTrue(app.staticTexts["NO. 496"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["已发现"].exists)
    }

    /// Seed a dedicated Simulator with a freshly created solid-color photo, then
    /// set TEST_RUNNER_ROCO_TEST_UNKNOWN_PHOTO=1 when invoking xcodebuild.
    func testUnknownPhotoCanBeReframedAndReturnToPreviousEntry() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ROCO_TEST_UNKNOWN_PHOTO"] == "1",
                          "This test needs a solid-color image as the newest photo.")
        lookup("010")
        importMostRecentPhoto()
        let miss = app.staticTexts["没有匹配到已收录的精灵"]
        XCTAssertTrue(miss.waitForExistence(timeout: 20), app.debugDescription)

        app.buttons["框选精灵"].tap()
        let slider = app.sliders["选框大小"]
        XCTAssertTrue(slider.waitForExistence(timeout: 6))
        let previousSize = slider.value as? String
        slider.adjust(toNormalizedSliderPosition: 0.26)
        XCTAssertNotEqual(slider.value as? String, previousSize)
        app.buttons["识别选中区域"].tap()
        XCTAssertTrue(slider.waitForNonExistence(timeout: 6))
        XCTAssertTrue(miss.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.buttons["框选精灵"].isHittable)

        app.buttons["返回精灵档案"].tap()
        XCTAssertTrue(app.buttons["查看特性和完整档案"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["NO. 010"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["水灵"].firstMatch.exists)
        XCTAssertFalse(miss.exists)
    }
}
