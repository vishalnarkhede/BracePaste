import XCTest
@testable import BracePaste

@MainActor
final class FormattedJSONViewModelTests: XCTestCase {
    private func makeSuccess() -> JSONProcessingResult.Success {
        JSONProcessingResult.Success(
            formattedJSON: "{\n  \"a\" : 1\n}",
            minifiedJSON: "{\"a\":1}",
            source: .exact,
            candidateRange: nil,
            originalInput: #"{"a":1}"#
        )
    }

    private func makeViewModel(
        canUndo: Bool = false,
        onCopy: @escaping (String) -> Void = { _ in },
        onUndo: @escaping () -> Void = {},
        onFormatAgain: @escaping (String) async -> JSONProcessingResult? = { _ in nil }
    ) -> FormattedJSONViewModel {
        FormattedJSONViewModel(
            wrapLongLines: false,
            onCopy: onCopy,
            onUndo: onUndo,
            onFormatAgain: onFormatAgain,
            onClose: {}
        )
    }

    func testCopyCurrent() {
        var copied: String?
        let vm = makeViewModel(onCopy: { copied = $0 })
        vm.applySuccess(makeSuccess(), confirmation: nil, canUndo: false)
        vm.copyCurrent()
        XCTAssertEqual(copied, vm.editorText)
        XCTAssertEqual(vm.confirmationMessage, "Copied")
    }

    func testCopyMinified() {
        var copied: String?
        let vm = makeViewModel(onCopy: { copied = $0 })
        vm.applySuccess(makeSuccess(), confirmation: nil, canUndo: false)
        vm.copyMinified()
        XCTAssertNotNil(copied)
        XCTAssertFalse(copied!.contains("\n"))
        XCTAssertEqual(vm.confirmationMessage, "Minified JSON copied")
    }

    func testFormatAgainSuccess() async {
        let vm = makeViewModel(onFormatAgain: { text in
            JSONExtractor.process(text, indentation: .twoSpaces)
        })
        vm.editorText = #"{"b":2}"#
        vm.formatAgain()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(vm.editorText.contains("b"))
        XCTAssertNil(vm.errorMessage)
    }

    func testUndoDisablesAfterUse() {
        var undone = false
        let vm = makeViewModel(canUndo: true, onUndo: { undone = true })
        vm.applySuccess(makeSuccess(), confirmation: nil, canUndo: true)
        vm.undo()
        XCTAssertTrue(undone)
        XCTAssertFalse(vm.canUndo)
    }

    func testShowLoadingThenSuccess() {
        let vm = makeViewModel()
        vm.showLoading()
        XCTAssertTrue(vm.isProcessing)
        XCTAssertEqual(vm.statusLabel, "Working…")
        vm.applySuccess(makeSuccess(), confirmation: "Formatted JSON copied to clipboard", canUndo: true)
        XCTAssertFalse(vm.isProcessing)
        XCTAssertTrue(vm.editorText.contains("a"))
        XCTAssertEqual(vm.confirmationMessage, "Formatted JSON copied to clipboard")
    }
}
