import XCTest

enum AccessibilityEvidenceDynamicType: String {
    case standard = "default"
    case ax5

    fileprivate var launchArguments: [String] {
        switch self {
        case .standard:
            ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        case .ax5:
            [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL"
            ]
        }
    }
}

enum AccessibilityEvidenceSeed {
    case firstRun
    case coreJourneys

    fileprivate var launchArgument: String {
        switch self {
        case .firstRun: "-ui-testing-first-run"
        case .coreJourneys: "-ui-testing-core-journeys"
        }
    }
}

/// Shared launch, evidence, and chrome-clearance contract for the explicit
/// accessibility matrix. Every test that calls `launchEvidenceCase` leaves a
/// screenshot and the full semantic hierarchy in its result bundle, including
/// when a later assertion fails.
@MainActor
class AccessibilityEvidenceUITestCase: XCTestCase {
    private(set) var app: XCUIApplication!

    private var evidenceName: String?
    private var evidenceMode: AccessibilityEvidenceDynamicType?

    private func attachEvidenceAndReset() {
        if let app, let evidenceName, let evidenceMode {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(evidenceName)-screenshot"
            screenshot.lifetime = .keepAlways
            add(screenshot)

            let hierarchy = XCTAttachment(
                string: """
                Evidence case: \(evidenceName)
                Dynamic Type: \(evidenceMode.rawValue)
                Simulator: \(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "unknown")

                \(app.debugDescription)
                """
            )
            hierarchy.name = "\(evidenceName)-accessibility-hierarchy"
            hierarchy.lifetime = XCTAttachment.Lifetime.keepAlways
            add(hierarchy)
        }

        app = nil
        evidenceName = nil
        evidenceMode = nil
    }

    func launchEvidenceCase(
        flow: String,
        mode: AccessibilityEvidenceDynamicType,
        seed: AccessibilityEvidenceSeed
    ) {
        continueAfterFailure = false
        evidenceName = "\(flow)-\(mode.rawValue)"
        evidenceMode = mode

        app = XCUIApplication()
        app.launchArguments = [seed.launchArgument] + mode.launchArguments
        app.launchEnvironment["OPENTV_ACCESSIBILITY_EVIDENCE_CASE"] = evidenceName
        app.launch()
        addTeardownBlock { @MainActor [weak self] in
            self?.attachEvidenceAndReset()
        }
    }
}

extension AccessibilityEvidenceUITestCase {
    func assertKeyActionIsReachableAndClear(
        _ element: XCUIElement,
        timeout: TimeInterval = 10,
        maximumScrolls: Int = 16,
        scrollContainer: XCUIElement? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if !element.waitForExistence(timeout: min(timeout, 2)) {
            for _ in 0..<maximumScrolls where !element.exists {
                nudgeScroll(upward: true, in: scrollContainer)
                _ = element.waitForExistence(timeout: 0.25)
            }
        }
        assertExists(element, timeout: 2, file: file, line: line)

        for _ in 0..<maximumScrolls {
            let frame = element.frame
            let visibleViewport = visibleViewport(
                for: element,
                within: scrollContainer
            )
            if frame.minY < visibleViewport.minY - 1 {
                nudgeScroll(upward: false, in: scrollContainer)
            } else if frame.maxY > visibleViewport.maxY + 1 {
                nudgeScroll(upward: true, in: scrollContainer)
            } else if !element.isHittable || isCoveredByInteractiveChrome(element) {
                nudgeScroll(upward: true, in: scrollContainer)
            } else {
                break
            }
        }

        XCTAssertTrue(
            element.isHittable,
            "Expected key action \(element) to be hittable",
            file: file,
            line: line
        )
        assertInsideViewport(
            element,
            viewport: visibleViewport(for: element, within: scrollContainer),
            file: file,
            line: line
        )

        assertNoInteractiveChromeOverlap(element, subject: "key action", file: file, line: line)
    }

    func assertExists(
        _ element: XCUIElement,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            "Expected \(element) to exist",
            file: file,
            line: line
        )
    }

    func assertEvidenceIsVisibleAndClear(
        _ element: XCUIElement,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertExists(element, timeout: timeout, file: file, line: line)

        // Product code owns the post-submission reveal. Poll only for the
        // layout/focus transition to settle; a test gesture here would mask a
        // response that the app itself left behind the composer.
        let settleDeadline = Date().addingTimeInterval(max(1, min(timeout, 3)))
        while Date() < settleDeadline && !isVisibleAndClear(element) {
            Thread.sleep(forTimeInterval: 0.1)
        }

        let visibleViewport = viewportExcludingInteractiveChrome(for: element)
        assertInsideViewport(
            element,
            viewport: visibleViewport,
            subject: "evidence element",
            file: file,
            line: line
        )
        assertNoInteractiveChromeOverlap(element, subject: "evidence element", file: file, line: line)
    }

    private func isVisibleAndClear(_ element: XCUIElement) -> Bool {
        let frame = element.frame
        let viewport = viewportExcludingInteractiveChrome(for: element)
        return !frame.isNull
            && !frame.isInfinite
            && !frame.isEmpty
            && frame.minX >= viewport.minX - 1
            && frame.maxX <= viewport.maxX + 1
            && frame.minY >= viewport.minY - 1
            && frame.maxY <= viewport.maxY + 1
            && !isCoveredByInteractiveChrome(element)
    }

    func selectRootTab(named name: String) {
        // iPhone exposes TabView controls under XCUIElementTypeTabBar. iPad's
        // floating tab presentation exposes the same semantic controls as top-
        // level buttons, so matching the user-facing tab label spans both.
        let tab = app.buttons.matching(
            NSPredicate(format: "label == %@", name)
        ).firstMatch
        assertExists(tab)
        tab.tap()
    }

    private func assertInsideViewport(
        _ element: XCUIElement,
        viewport: CGRect? = nil,
        subject: String = "key action",
        file: StaticString,
        line: UInt
    ) {
        let actionFrame = element.frame
        let viewport = viewport ?? app.frame
        XCTAssertFalse(
            actionFrame.isNull || actionFrame.isInfinite || actionFrame.isEmpty,
            "Expected \(subject) to expose a finite, non-empty frame; received \(actionFrame)",
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            actionFrame.minX,
            viewport.minX - 1,
            "Expected \(subject) to clear the leading viewport edge",
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            actionFrame.maxX,
            viewport.maxX + 1,
            "Expected \(subject) to clear the trailing viewport edge",
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            actionFrame.minY,
            viewport.minY - 1,
            "Expected \(subject) to clear the top viewport edge",
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            actionFrame.maxY,
            viewport.maxY + 1,
            "Expected \(subject) to clear the bottom viewport edge",
            file: file,
            line: line
        )
    }

    private func isCoveredByInteractiveChrome(_ element: XCUIElement) -> Bool {
        interactiveChromeElements(excludingContainersOf: element).contains { chrome in
            let overlap = element.frame.intersection(chrome.frame)
            return !overlap.isNull && overlap.width > 1 && overlap.height > 1
        }
    }

    private func viewportExcludingInteractiveChrome(for element: XCUIElement? = nil) -> CGRect {
        let viewport = app.frame
        var top = viewport.minY
        var bottom = viewport.maxY

        for chrome in interactiveChromeElements(excludingContainersOf: element) {
            let frame = chrome.frame.intersection(viewport)
            guard !frame.isNull, frame.width > 1, frame.height > 1 else { continue }
            if frame.midY <= viewport.midY {
                top = max(top, frame.maxY)
            } else {
                bottom = min(bottom, frame.minY)
            }
        }

        return CGRect(
            x: viewport.minX,
            y: top,
            width: viewport.width,
            height: max(0, bottom - top)
        )
    }

    private func visibleViewport(
        for element: XCUIElement,
        within scrollContainer: XCUIElement?
    ) -> CGRect {
        let chromeClearViewport = viewportExcludingInteractiveChrome(for: element)
        guard let scrollContainer else { return chromeClearViewport }
        return chromeClearViewport.intersection(scrollContainer.frame)
    }

    private func nudgeScroll(upward: Bool, in scrollContainer: XCUIElement? = nil) {
        let surface = scrollContainer ?? app!
        let startY: CGFloat
        let endY: CGFloat
        if scrollContainer == nil {
            startY = upward ? 0.72 : 0.38
            endY = upward ? 0.52 : 0.58
        } else {
            startY = upward ? 0.65 : 0.35
            endY = upward ? 0.45 : 0.55
        }
        let start = surface.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: startY)
        )
        let end = surface.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: endY)
        )
        start.press(
            forDuration: 0.1,
            thenDragTo: end,
            withVelocity: .slow,
            thenHoldForDuration: 0.1
        )
    }

    private func assertNoInteractiveChromeOverlap(
        _ element: XCUIElement,
        subject: String,
        file: StaticString,
        line: UInt
    ) {
        for chrome in interactiveChromeElements(excludingContainersOf: element) {
            let overlap = element.frame.intersection(chrome.frame)
            XCTAssertTrue(
                overlap.isNull || overlap.width <= 1 || overlap.height <= 1,
                "Expected \(subject) \(element) not to overlap interactive chrome \(chrome); overlap was \(overlap)",
                file: file,
                line: line
            )
        }
    }

    private func interactiveChromeElements(
        excludingContainersOf target: XCUIElement? = nil
    ) -> [XCUIElement] {
        let floatingRootTabs = app.buttons.matching(
            NSPredicate(format: "label IN %@", ["Today", "Library", "Discover"])
        ).allElementsBoundByIndex
        let chrome = app.navigationBars.allElementsBoundByIndex
            + app.tabBars.allElementsBoundByIndex
            + app.toolbars.allElementsBoundByIndex
            + app.keyboards.allElementsBoundByIndex
            + floatingRootTabs
            + app.descendants(matching: .any).matching(identifier: "assistant.composer").allElementsBoundByIndex
        return chrome.filter { chromeElement in
            guard chromeElement.exists else { return false }
            let frame = chromeElement.frame
            let isVisibleInApp = !frame.isNull
                && !frame.isInfinite
                && !frame.isEmpty
                && frame.intersects(app.frame)
            guard isVisibleInApp else { return false }

            // A software keyboard is interactive chrome even though XCUI can
            // report its container as non-hittable. Keep the query at the
            // keyboard boundary; enumerating every key is both unnecessary and
            // vulnerable to hierarchy-query watchdog stalls.
            if chromeElement.elementType == .keyboard { return true }

            // This is the only intentional target/chrome containment. Keep the
            // stable-ID pair narrow to avoid recursive XCUI descendant queries
            // that can stall until the test-runner watchdog terminates the run.
            if chromeElement.identifier == "assistant.composer",
               target?.identifier == "assistant.find-picks" {
                return false
            }
            if chromeElement.isHittable { return true }
            guard chromeElement.elementType == .navigationBar
                || chromeElement.elementType == .tabBar
                || chromeElement.elementType == .toolbar
                || chromeElement.identifier == "assistant.composer" else {
                return false
            }
            // A bounded probe preserves container coverage without walking the
            // complete hierarchy of an obscured navigation or tab container.
            return chromeElement.buttons.firstMatch.isHittable
        }
    }
}
