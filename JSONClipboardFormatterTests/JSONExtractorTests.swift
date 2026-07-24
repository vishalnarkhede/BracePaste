import XCTest
@testable import BracePaste

final class JSONExtractorTests: XCTestCase {
    func testValidObject() {
        let input = #"{"name":"Alice","active":true}"#
        let result = JSONExtractor.process(input)
        let success = try! XCTUnwrap(result.success)
        XCTAssertEqual(success.source, .exact)
        XCTAssertTrue(success.formattedJSON.contains("\"name\" : \"Alice\"") || success.formattedJSON.contains("\"name\": \"Alice\""))
        XCTAssertTrue(success.minifiedJSON.contains("Alice"))
    }

    func testValidArray() {
        let input = #"[{"id":1},{"id":2}]"#
        let result = JSONExtractor.process(input)
        let success = try! XCTUnwrap(result.success)
        XCTAssertEqual(success.source, .exact)
        XCTAssertTrue(success.formattedJSON.hasPrefix("["))
    }

    func testPrimitiveJSONValueRejectedForPrimaryPath() {
        let result = JSONExtractor.process("42")
        XCTAssertFalse(result.isSuccess)
    }

    func testDeeplyNestedJSON() {
        let input = #"{"a":{"b":{"c":{"d":[1,2,{"e":true}]}}}}"#
        let result = JSONExtractor.process(input)
        XCTAssertTrue(result.isSuccess)
    }

    func testEmptyObject() {
        let result = JSONExtractor.process("{}")
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.success?.formattedJSON.trimmingCharacters(in: .whitespacesAndNewlines), "{}")
    }

    func testEmptyArray() {
        let result = JSONExtractor.process("[]")
        XCTAssertTrue(result.isSuccess)
    }

    func testUnicodeValues() {
        let input = #"{"msg":"你好🌍","emoji":"🎉"}"#
        let result = JSONExtractor.process(input)
        let success = try! XCTUnwrap(result.success)
        XCTAssertTrue(success.formattedJSON.contains("你好") || success.formattedJSON.contains("\\u"))
    }

    func testEscapedQuotesInsideStrings() {
        let input = #"{"quote":"She said \"hi\""}"#
        let result = JSONExtractor.process(input)
        XCTAssertTrue(result.isSuccess)
    }

    func testEscapedBackslashes() {
        let input = #"{"path":"C:\\Users\\Alice"}"#
        let result = JSONExtractor.process(input)
        XCTAssertTrue(result.isSuccess)
    }

    func testBracesInsideStrings() {
        let input = #"{"text":"not an object { or } here"}"#
        let result = JSONExtractor.process(input)
        XCTAssertEqual(result.success?.source, .exact)
    }

    func testBracketsInsideStrings() {
        let input = #"{"text":"array [1,2] lookalike"}"#
        let result = JSONExtractor.process(input)
        XCTAssertEqual(result.success?.source, .exact)
    }

    func testLabelledJSONCodeFence() {
        let input = """
        Here is the response:

        ```json
        {"status":"ok","items":[1,2,3]}
        ```
        """
        let result = JSONExtractor.process(input)
        let success = try! XCTUnwrap(result.success)
        XCTAssertEqual(success.source, .labelledCodeFence)
        XCTAssertTrue(success.formattedJSON.contains("status"))
    }

    func testUnlabelledCodeFence() {
        let input = """
        Result:

        ```
        {"status":"ok"}
        ```
        """
        let result = JSONExtractor.process(input)
        let success = try! XCTUnwrap(result.success)
        XCTAssertEqual(success.source, .unlabelledCodeFence)
    }

    func testJSONSurroundedByLogText() {
        let input = #"Agent result: payload={"status":"ok","count":3} completed successfully"#
        let result = JSONExtractor.process(input)
        let success = try! XCTUnwrap(result.success)
        XCTAssertEqual(success.source, .surroundingText)
        XCTAssertTrue(success.minifiedJSON.contains("\"count\":3") || success.minifiedJSON.contains("\"count\": 3"))
    }

    func testEscapedJSONString() {
        let input = #""{\"status\":\"ok\",\"user\":{\"id\":42}}""#
        let result = JSONExtractor.process(input)
        let success = try! XCTUnwrap(result.success)
        XCTAssertEqual(success.source, .escapedJSON)
        XCTAssertTrue(success.formattedJSON.contains("user"))
    }

    func testNestedInsideExplanatoryOutput() {
        let input = """
        The SQL query returned the following value:
        response={"success":true,"rows":[{"id":1,"name":"Alice"}]}
        Execution completed.
        """
        let result = JSONExtractor.process(input)
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.success?.source, .surroundingText)
    }

    func testMultipleCandidatesLargestSelected() {
        let input = #"small={"a":1} large={"a":1,"b":2,"c":3,"d":4}"#
        let result = JSONExtractor.process(input)
        let success = try! XCTUnwrap(result.success)
        XCTAssertTrue(success.minifiedJSON.contains("d") || success.formattedJSON.contains("\"d\""))
    }

    func testLabelledFenceBeatsSurroundingText() {
        let input = """
        noise={"ignored":true}
        ```json
        {"chosen":true}
        ```
        """
        let result = JSONExtractor.process(input)
        XCTAssertEqual(result.success?.source, .labelledCodeFence)
        XCTAssertTrue(result.success?.formattedJSON.contains("chosen") == true)
    }

    func testExactBeatsSurroundingWhenEntireInputIsJSON() {
        let input = #"{"only":true}"#
        let result = JSONExtractor.process(input)
        XCTAssertEqual(result.success?.source, .exact)
    }

    func testInvalidJSON() {
        let result = JSONExtractor.process("This is not JSON.")
        XCTAssertFalse(result.isSuccess)
        XCTAssertEqual(
            result.failure?.message,
            "No valid JSON object or array was found in the clipboard."
        )
    }

    func testSoftWrappedNewlineInsideStringLiteral() {
        // Chat soft-wrap often splits mid-value: "MacBook" + newline + "Pro"
        let input = "{\"device\":\"MacBook\nPro\",\"city\":\"Amsterdam\"}"
        let result = JSONExtractor.process(input)
        XCTAssertTrue(result.isSuccess)
        XCTAssertTrue(result.success?.formattedJSON.contains("MacBook Pro") == true)
    }

    func testSoftWrappedNewlineWithIndentInsideStringLiteral() {
        let input = "{\"device\":\"MacBook\n  Pro\"}"
        let result = JSONExtractor.process(input)
        XCTAssertTrue(result.isSuccess)
        XCTAssertTrue(result.success?.formattedJSON.contains("MacBook Pro") == true)
    }

    func testPrettyPrintedJSONStillParses() {
        let input = """
        {
          "device": "MacBook Pro",
          "city": "Amsterdam"
        }
        """
        let result = JSONExtractor.process(input)
        XCTAssertTrue(result.isSuccess)
        XCTAssertTrue(result.success?.formattedJSON.contains("MacBook Pro") == true)
    }

    func testIncompleteJSON() {
        let result = JSONExtractor.process(#"{"name":"Alice""#)
        XCTAssertFalse(result.isSuccess)
    }

    func testTrailingCommasRejected() {
        let result = JSONExtractor.process(#"{"a":1,}"#)
        XCTAssertFalse(result.isSuccess)
    }

    func testSingleQuotedInputRejected() {
        let result = JSONExtractor.process("{'a': 1}")
        XCTAssertFalse(result.isSuccess)
    }

    func testPythonDictionaryRejected() {
        let result = JSONExtractor.process("{'name': 'Alice', 'active': True}")
        XCTAssertFalse(result.isSuccess)
    }

    func testLargeJSONPayload() {
        var items: [String] = []
        for i in 0..<5_000 {
            items.append(#"{"id":\#(i),"name":"item\#(i)"}"#)
        }
        let input = "[" + items.joined(separator: ",") + "]"
        let result = JSONExtractor.process(input)
        XCTAssertTrue(result.isSuccess)
    }

    func testIndentationTwoSpacesDefault() {
        let result = JSONExtractor.process(#"{"a":{"b":1}}"#, indentation: .twoSpaces)
        let formatted = try! XCTUnwrap(result.success?.formattedJSON)
        XCTAssertTrue(formatted.contains("\n  "))
    }

    func testIndentationFourSpaces() {
        let result = JSONExtractor.process(#"{"a":{"b":1}}"#, indentation: .fourSpaces)
        let formatted = try! XCTUnwrap(result.success?.formattedJSON)
        XCTAssertTrue(formatted.contains("\n    "))
    }

    func testIndentationTabs() {
        let result = JSONExtractor.process(#"{"a":{"b":1}}"#, indentation: .tabs)
        let formatted = try! XCTUnwrap(result.success?.formattedJSON)
        XCTAssertTrue(formatted.contains("\n\t"))
    }
}

final class BalancedJSONScannerTests: XCTestCase {
    func testNestedObjectsAndArrays() {
        let text = #"prefix {"a":[1,{"b":2}]} suffix"#
        let candidates = BalancedJSONScanner.findCandidates(in: text)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].text, #"{"a":[1,{"b":2}]}"#)
    }

    func testIgnoresBracesInStrings() {
        let text = #"{"x":"yes { no }"}"#
        let candidates = BalancedJSONScanner.findCandidates(in: text)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].text, text)
    }

    func testEscapedQuotesInStrings() {
        let text = #"{"q":"say \"}\""}"#
        let candidates = BalancedJSONScanner.findCandidates(in: text)
        XCTAssertEqual(candidates.count, 1)
    }

    func testIncompleteStructureIgnored() {
        let text = #"{"open": true"#
        let candidates = BalancedJSONScanner.findCandidates(in: text)
        XCTAssertTrue(candidates.isEmpty)
    }
}

@MainActor
final class DoubleCopyMonitorTests: XCTestCase {
    func testDoubleCopyWithinInterval() {
        let monitor = DoubleCopyMonitor()
        monitor.interval = 0.45
        monitor.enableForTesting()
        var fired = false
        monitor.onDoubleCopy = { _ in fired = true }

        monitor.handleKeyEventForTesting(
            keyCode: 8, characters: "c", modifiers: .command, isARepeat: false, pasteboardChangeCount: 1
        )
        monitor.handleKeyEventForTesting(
            keyCode: 8, characters: "c", modifiers: .command, isARepeat: false, pasteboardChangeCount: 2
        )
        XCTAssertTrue(fired)
    }

    func testExpiredDoubleCopyTiming() async {
        let monitor = DoubleCopyMonitor()
        monitor.interval = 0.05
        monitor.enableForTesting()
        var fireCount = 0
        monitor.onDoubleCopy = { _ in fireCount += 1 }

        monitor.handleKeyEventForTesting(
            keyCode: 8, characters: "c", modifiers: .command, isARepeat: false, pasteboardChangeCount: 1
        )
        try? await Task.sleep(nanoseconds: 80_000_000)
        monitor.handleKeyEventForTesting(
            keyCode: 8, characters: "c", modifiers: .command, isARepeat: false, pasteboardChangeCount: 2
        )
        XCTAssertEqual(fireCount, 0)
    }

    func testIgnoresKeyRepeat() {
        let monitor = DoubleCopyMonitor()
        monitor.enableForTesting()
        var fired = false
        monitor.onDoubleCopy = { _ in fired = true }

        monitor.handleKeyEventForTesting(
            keyCode: 8, characters: "c", modifiers: .command, isARepeat: false, pasteboardChangeCount: 1
        )
        monitor.handleKeyEventForTesting(
            keyCode: 8, characters: "c", modifiers: .command, isARepeat: true, pasteboardChangeCount: 1
        )
        XCTAssertFalse(fired)
    }

    func testExtraModifierKeysIgnored() {
        let monitor = DoubleCopyMonitor()
        monitor.enableForTesting()
        var fired = false
        monitor.onDoubleCopy = { _ in fired = true }

        monitor.handleKeyEventForTesting(
            keyCode: 8, characters: "c", modifiers: [.command, .shift], isARepeat: false, pasteboardChangeCount: 1
        )
        monitor.handleKeyEventForTesting(
            keyCode: 8, characters: "c", modifiers: .command, isARepeat: false, pasteboardChangeCount: 2
        )
        // Second press alone starts a new gesture; need another Cmd+C
        XCTAssertFalse(fired)
        monitor.handleKeyEventForTesting(
            keyCode: 8, characters: "c", modifiers: .command, isARepeat: false, pasteboardChangeCount: 3
        )
        XCTAssertTrue(fired)
    }
}

@MainActor
final class ClipboardUndoManagerTests: XCTestCase {
    func testSuccessfulUndo() {
        let pb = NSPasteboard.withUniqueName()
        let clipboard = ClipboardManager(pasteboard: pb)
        let undo = ClipboardUndoManager(clipboard: clipboard)

        let original = clipboard.writePlainText("original")!
        let written = clipboard.writePlainText("formatted")!
        undo.recordReplacement(original: original, written: written)

        XCTAssertTrue(undo.canUndo)
        XCTAssertTrue(undo.undoIfSafe())
        XCTAssertEqual(clipboard.readPlainText(), "original")
        XCTAssertFalse(undo.canUndo)
    }

    func testBlockedUndoAfterNewerClipboardContent() {
        let pb = NSPasteboard.withUniqueName()
        let clipboard = ClipboardManager(pasteboard: pb)
        let undo = ClipboardUndoManager(clipboard: clipboard)

        let original = clipboard.writePlainText("original")!
        let written = clipboard.writePlainText("formatted")!
        undo.recordReplacement(original: original, written: written)

        _ = clipboard.writePlainText("user copied something else")
        XCTAssertFalse(undo.canUndo)
        XCTAssertFalse(undo.undoIfSafe())
        XCTAssertEqual(clipboard.readPlainText(), "user copied something else")
    }

    func testSafeOverwriteTracking() {
        let pb = NSPasteboard.withUniqueName()
        let clipboard = ClipboardManager(pasteboard: pb)
        let before = clipboard.changeCount
        let snap = clipboard.writePlainText(#"{"a":1}"#)
        XCTAssertNotNil(snap)
        XCTAssertNotEqual(clipboard.changeCount, before)
    }
}

@MainActor
final class AppSettingsTests: XCTestCase {
    func testPersistence() {
        let suiteName = "JSONClipboardFormatterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.doubleCopyIntervalMs = 600
        settings.indentation = .fourSpaces
        settings.doubleCopyEnabled = false
        settings.replaceClipboardAutomatically = false

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.doubleCopyIntervalMs, 600)
        XCTAssertEqual(reloaded.indentation, .fourSpaces)
        XCTAssertFalse(reloaded.doubleCopyEnabled)
        XCTAssertFalse(reloaded.replaceClipboardAutomatically)
    }

    func testIntervalClamped() {
        let suiteName = "JSONClipboardFormatterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.doubleCopyIntervalMs = 100
        XCTAssertEqual(settings.doubleCopyIntervalMs, 250)
        settings.doubleCopyIntervalMs = 900
        XCTAssertEqual(settings.doubleCopyIntervalMs, 900)
        settings.doubleCopyIntervalMs = 5000
        XCTAssertEqual(settings.doubleCopyIntervalMs, 3000)
    }
}

final class CandidateSelectionDocumentationTests: XCTestCase {
    /// Documents priority:
    /// 1 labelled fence, 2 exact/escaped, 3 unlabelled fence, 4 largest surrounding.
    func testCandidateSelectionRules() {
        // 1 over 4
        let labelledWins = JSONExtractor.process("""
        {"noise":1}
        ```json
        {"win":1}
        ```
        """)
        XCTAssertEqual(labelledWins.success?.source, .labelledCodeFence)

        // 2 exact over surrounding (exact is entire input)
        let exact = JSONExtractor.process(#"{"exact":true}"#)
        XCTAssertEqual(exact.success?.source, .exact)

        // 3 unlabelled when no labelled / exact
        let unlabelled = JSONExtractor.process("""
        text
        ```
        {"u":1}
        ```
        more
        """)
        XCTAssertEqual(unlabelled.success?.source, .unlabelledCodeFence)

        // 4 largest surrounding
        let surrounding = JSONExtractor.process(#"a={"x":1} b={"x":1,"y":2}"#)
        XCTAssertEqual(surrounding.success?.source, .surroundingText)
        XCTAssertTrue(surrounding.success?.formattedJSON.contains("y") == true)
    }
}
