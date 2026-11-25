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

    func testAnimatedPortraitDefaultsToMotionOnEachVisit() throws {
        lookup("219")
        let toggle = app.buttons["portraitMediaToggle"]
        let animation = app.descendants(matching: .any).matching(identifier: "animationViewport").firstMatch
        let still = app.images["staticPortrait"]
        XCTAssertTrue(animation.waitForExistence(timeout: 8))
        XCTAssertEqual(toggle.value as? String, "动图")
        let idle = NSPredicate { _, _ in
            (animation.value as? String)?.hasPrefix("待机") == true
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: idle, object: nil)], timeout: 6), .completed)
        let firstFrame = try XCTUnwrap(animation.value as? String)
        let moves = NSPredicate { _, _ in
            guard let value = animation.value as? String else { return false }
            return value != firstFrame && value.hasPrefix("待机")
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: moves, object: nil)], timeout: 5), .completed)
        toggle.tap()
        XCTAssertTrue(still.waitForExistence(timeout: 5))
        XCTAssertFalse(animation.exists)
        app.buttons["向右"].tap()
        app.buttons["向左"].tap()
        XCTAssertTrue(still.waitForExistence(timeout: 5), "Browsing the same card should keep the manual still-image choice")

        lookup("219")
        XCTAssertTrue(animation.waitForExistence(timeout: 8), "Selecting the same spirit again starts a new visit")
        XCTAssertEqual(toggle.value as? String, "动图")
        lookup("005")
        XCTAssertTrue(still.waitForExistence(timeout: 5))
        XCTAssertFalse(toggle.exists)
        XCTAssertFalse(animation.exists)
        lookup("008")
        XCTAssertTrue(animation.waitForExistence(timeout: 5), "Existing single-clip animations still loop")
        XCTAssertTrue(app.buttons["portraitNarration"].isHittable)
    }

    func testBlueLampRespondsDuringNarration() throws {
        lookup("008")
        let lens = app.descendants(matching: .any).matching(identifier: "narrationLamp").firstMatch
        XCTAssertTrue(lens.waitForExistence(timeout: 5))
        XCTAssertEqual(lens.frame.width, lens.frame.height, accuracy: 1)
        XCTAssertEqual(lens.value as? String, "待机")

        // A one-pixel downsample averages the entire cropped lens, independent of pixel density.
        func brightness() throws -> Int {
            let bitmap = try XCTUnwrap(lens.screenshot().image.cgImage)
            let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            context.interpolationQuality = .high
            context.draw(bitmap, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            let rgb = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
            return Int(rgb[0]) + Int(rgb[1]) + Int(rgb[2])
        }

        let idle = try brightness()
        capture("lamp-before-narration")
        app.buttons["portraitNarration"].tap()
        XCTAssertEqual(lens.value as? String, "正在播报")
        var lit = [Int]()
        for _ in 0..<6 { lit.append(try brightness()) }
        print("LAMP_CHECK baseline=\(idle) speaking=\(lit)")
        XCTAssertGreaterThan(try XCTUnwrap(lit.max()), idle + 7)
        app.buttons["portraitNarration"].tap()
        XCTAssertEqual(lens.value as? String, "待机")
        XCTAssertEqual(try brightness(), idle, accuracy: 4)
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
        XCTAssertFalse(app.links["查看原始图鉴"].exists)
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
        XCTAssertTrue(app.staticTexts["进化"].firstMatch.waitForExistence(timeout: 3))
        let middle = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "喵呜")).firstMatch
        XCTAssertTrue(middle.waitForExistence(timeout: 3))
        middle.tap()
        XCTAssertTrue(app.staticTexts["NO. 003"].firstMatch.waitForExistence(timeout: 3))
        app.buttons["向右"].tap()
        XCTAssertTrue(app.staticTexts["生态与获取"].waitForExistence(timeout: 3))
        app.buttons["向右"].tap()
        XCTAssertTrue(app.staticTexts["档案"].exists)
        XCTAssertTrue(app.staticTexts["喵呜"].firstMatch.exists)
    }

    private func capture(_ name: String) {
        XCTContext.runActivity(named: "Screenshot-" + name) { activity in
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
    }

    private func showCompanionPage(_ page: Int) {
        if app.buttons["看资料"].exists { app.buttons["看资料"].tap() }
        let tab = app.buttons["rightTab-" + String(page)]
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        XCTAssertTrue(tab.isSelected, "右侧资料页应与档案翻页同步")
    }

    private func returnToPortrait() {
        if app.buttons["看档案"].exists { app.buttons["看档案"].tap() }
        XCTAssertTrue(app.buttons["向右"].waitForExistence(timeout: 5))
    }

    private func visible(_ query: XCUIElementQuery, file: StaticString = #filePath, line: UInt = #line) throws -> XCUIElement {
        let appears = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            query.allElementsBoundByIndex.contains(where: { $0.isHittable })
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [appears], timeout: 5), .completed, file: file, line: line)
        return try XCTUnwrap(query.allElementsBoundByIndex.first(where: { $0.isHittable }), file: file, line: line)
    }

    func testDuoFormProfileAndSkillsStayInSync() {
        lookup("001")
        app.buttons["chooseForm"].tap()
        let form = app.buttons["entry-10560"]
        XCTAssertTrue(form.waitForExistence(timeout: 5), app.debugDescription)
        form.tap()
        XCTAssertTrue(app.staticTexts["圣火迪莫"].firstMatch.waitForExistence(timeout: 5))
        capture("01-fire-dimo-portrait")
        showCompanionPage(0)
        XCTAssertTrue(app.staticTexts["点燃"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["598"].exists)
        capture("02-fire-dimo-stats")

        app.buttons["rightTab-1"].tap()
        XCTAssertTrue(app.buttons["skill-level-skill_000248"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["skill-level-skill_000398"].exists)
        capture("03-fire-dimo-skills")
        returnToPortrait()
        XCTAssertTrue(app.staticTexts["进化"].firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "圣火迪莫")).firstMatch.exists)
    }

    func testDuoEvolutionAndSkillDetail() throws {
        lookup("013")
        app.buttons["向右"].tap()
        XCTAssertTrue(app.staticTexts["进化"].firstMatch.waitForExistence(timeout: 3))
        for name in ["板板壳", "咔咔壳", "水泡壳"] {
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch.exists, name)
        }
        capture("04-shell-evolution")
        showCompanionPage(1)
        let soap = app.buttons["skill-level-skill_000436"]
        XCTAssertTrue(soap.waitForExistence(timeout: 5))
        app.buttons["skillExpand"].tap()
        XCTAssertTrue(app.buttons["收起技能图鉴"].waitForExistence(timeout: 5))
        let filter = try visible(app.buttons.matching(identifier: "skillFilter-level"))
        filter.tap()
        XCTAssertTrue(filter.isSelected)
        let search = try visible(app.textFields.matching(identifier: "skillSearch"))
        search.tap()
        search.typeText("Lv.34\n")
        let waterCannon = app.buttons["skill-level-skill_000422"].firstMatch
        XCTAssertTrue(waterCannon.waitForExistence(timeout: 5))
        XCTAssertFalse(soap.firstMatch.exists)
        try visible(app.buttons.matching(identifier: "清空搜索")).tap()
        let shownSoap = try visible(app.buttons.matching(identifier: "skill-level-skill_000436"))
        capture("05-shell-skill-guide")
        shownSoap.tap()
        let close = app.buttons["skillDetailClose"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        for value in ["肥皂泡", "水系", "魔攻", "威力", "60", "能耗", "1", "自学 · Lv.1", "对敌方精灵造成魔法伤害。"] {
            XCTAssertTrue(app.staticTexts[value].firstMatch.exists, value)
        }
        capture("06-soap-bubble-detail")
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        let collapse = app.buttons["收起技能图鉴"].firstMatch
        XCTAssertTrue(collapse.waitForExistence(timeout: 5))
        collapse.tap()
        returnToPortrait()
        XCTAssertTrue(app.staticTexts["进化"].firstMatch.exists)
    }

    func testDuoHabitatAndInteractiveMap() {
        lookup("046")
        app.buttons["向左"].tap()
        XCTAssertTrue(app.staticTexts["生态与获取"].waitForExistence(timeout: 5))
        let knownAreas = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "风息山口", "风眠圣所"))
        XCTAssertTrue(knownAreas.firstMatch.exists)
        capture("07-kawazhong-habitat")
        showCompanionPage(2)
        let open = app.buttons["expandHabitatMap"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertTrue(open.label.contains("卡瓦重"))
        capture("08-kawazhong-map-preview")
        open.tap()
        let ritualTown = app.buttons["仪式镇"]
        XCTAssertTrue(ritualTown.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["信仰者村落"].exists)
        XCTAssertFalse(app.links["地图来源"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "洛克王国世界 WIKI")).firstMatch.exists)
        capture("09-kawazhong-map")
        ritualTown.tap()
        XCTAssertTrue(app.staticTexts["精灵栖息地 · 洛克里安 · 仪式镇"].waitForExistence(timeout: 5))
        app.buttons["重置视角"].tap()
        app.buttons["closeHabitatMap"].tap()
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        app.buttons["rightTab-0"].tap()
        returnToPortrait()
        XCTAssertTrue(app.buttons["查看特性和完整档案"].waitForExistence(timeout: 5))

        lookup("008")
        app.buttons["向左"].tap()
        XCTAssertTrue(app.staticTexts["水蓝蓝的果实"].firstMatch.waitForExistence(timeout: 5))
        showCompanionPage(2)
        open.tap()
        XCTAssertTrue(app.staticTexts["当前地图尚未收录该形态的野外定位。"].waitForExistence(timeout: 5))
        app.buttons["closeHabitatMap"].tap()
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

    func testIndexElementFiltersCombineWithDexNumber() {
        openKeypad()
        app.buttons["按编号查找"].tap()
        XCTAssertTrue(app.navigationBars["精灵名册"].waitForExistence(timeout: 5))
        let fire = app.buttons["火系，62 个形态"]
        XCTAssertTrue(fire.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["水系，84 个形态"].exists)
        fire.tap()
        XCTAssertTrue(fire.isSelected)
        capture("10-index-elements")

        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("001\n")
        let fireDimo = app.buttons["entry-10560"]
        XCTAssertTrue(fireDimo.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["entry-1"].exists)
        XCTAssertFalse(app.buttons["entry-10561"].exists)
        fireDimo.tap()
        XCTAssertTrue(app.staticTexts["圣火迪莫"].firstMatch.waitForExistence(timeout: 5))
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

    private func openAudioPreferences() {
        openKeypad()
        app.buttons["精灵资料"].tap()
        XCTAssertTrue(app.switches["feedbackSoundToggle"].firstMatch.waitForExistence(timeout: 5))
    }

    private func setSwitch(_ name: String, to enabled: Bool) {
        let control = app.switches[name].firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        let expected = enabled ? "1" : "0"
        if control.value as? String != expected {
            // A SwiftUI List exposes the whole row as a switch, with the native control at its trailing edge.
            let thumb = control.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5))
            thumb.tap()
        }
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: control)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 3), .completed)
    }

    func testMutedFeedbackAndDisabledAutoVoicePersistIndependently() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ROCO_TEST_PHOTO"] == "1",
                          "Seed the simulator with the Water Blue portrait before scanning.")
        openAudioPreferences()
        setSwitch("识别成功时朗读", to: false)
        setSwitch("feedbackSoundToggle", to: true)
        setSwitch("feedbackSoundToggle", to: false)
        XCTAssertEqual(app.switches["识别成功时朗读"].firstMatch.value as? String, "0")
        app.terminate()
        app.launch()

        openAudioPreferences()
        XCTAssertEqual(app.switches["feedbackSoundToggle"].firstMatch.value as? String, "0")
        XCTAssertEqual(app.switches["识别成功时朗读"].firstMatch.value as? String, "0")
        app.buttons["完成"].tap()

        lookup("002")
        importMostRecentPhoto()
        XCTAssertTrue(app.staticTexts["NO. 008"].firstMatch.waitForExistence(timeout: 15))
        let playing = app.buttons["停止介绍"].firstMatch
        XCTAssertFalse(playing.waitForExistence(timeout: 1.5), "Explicitly disabled auto narration must stay silent after a scan")
        let manual = app.buttons["portraitNarration"]
        manual.tap()
        XCTAssertTrue(playing.waitForExistence(timeout: 5), "Muting effects must still allow manual narration")
        manual.tap()
        XCTAssertTrue(app.buttons["播放介绍"].firstMatch.waitForExistence(timeout: 5))
        openAudioPreferences()
        setSwitch("feedbackSoundToggle", to: true)
        XCTAssertEqual(app.switches["识别成功时朗读"].firstMatch.value as? String, "0")
        setSwitch("识别成功时朗读", to: true)
        app.buttons["完成"].tap()
    }

    /// Run on a dedicated Simulator after adding Art/008.png as its newest photo
    /// and setting TEST_RUNNER_ROCO_TEST_PHOTO=1 on the xcodebuild invocation.
    func testImportedWaterBluePhotoOpensDiscoveredEntry() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ROCO_TEST_PHOTO"] == "1",
                          "Seed a dedicated Simulator with Art/008.png to exercise PHPicker import.")
        openAudioPreferences()
        setSwitch("识别成功时朗读", to: true)
        setSwitch("feedbackSoundToggle", to: true)
        app.buttons["完成"].tap()
        lookup("002")
        importMostRecentPhoto()
        XCTAssertTrue(app.staticTexts["已发现"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.staticTexts["NO. 008"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["水蓝蓝"].firstMatch.exists)
        XCTAssertTrue(app.buttons["停止介绍"].firstMatch.waitForExistence(timeout: 4),
                      "Discovery with confirmation effects enabled should automatically introduce the matched spirit")
        app.buttons["portraitNarration"].tap()
        XCTAssertTrue(app.buttons["播放介绍"].firstMatch.waitForExistence(timeout: 3))
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
