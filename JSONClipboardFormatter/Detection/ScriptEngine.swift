import Foundation
import JavaScriptCore

/// Runs the bundled open-source libraries (highlight.js for language
/// classification, sql-formatter for SQL parsing/formatting) inside
/// JavaScriptCore. Everything stays on-device; the context is created once
/// and guarded by a lock since JSContext is not thread-safe.
final class ScriptEngine: @unchecked Sendable {
    static let shared = ScriptEngine()

    struct LanguageGuess: Equatable {
        let language: String?
        let relevance: Double
        let secondLanguage: String?
        let secondRelevance: Double
    }

    enum SQLDialect: String {
        case postgresql
        case mysql
        case standard = "sql"
    }

    /// Languages hljs is allowed to choose between. Restricting the set makes
    /// relevance scores meaningful for our use case.
    static let detectionSubset = [
        "json", "sql", "go", "swift", "javascript", "typescript", "python",
        "java", "kotlin", "rust", "cpp", "csharp", "ruby", "php", "yaml",
        "bash", "plaintext"
    ]

    /// Languages that indicate the clipboard holds source code.
    static let codeLanguages: Set<String> = [
        "go", "swift", "javascript", "typescript", "python", "java", "kotlin",
        "rust", "cpp", "csharp", "ruby", "php", "bash"
    ]

    private let lock = NSLock()
    private var context: JSContext?
    private var loadFailed = false

    private func loadedContext() -> JSContext? {
        if let context { return context }
        if loadFailed { return nil }

        guard let context = JSContext() else {
            loadFailed = true
            return nil
        }
        for script in ["highlight.min", "sql-formatter.min", "sql-parser.umd"] {
            guard let url = Bundle.main.url(forResource: script, withExtension: "js", subdirectory: "JS")
                    ?? Bundle.main.url(forResource: script, withExtension: "js"),
                  let source = try? String(contentsOf: url, encoding: .utf8) else {
                loadFailed = true
                return nil
            }
            context.evaluateScript(source)
            if context.exception != nil {
                loadFailed = true
                return nil
            }
        }
        self.context = context
        return context
    }

    /// Classifies `text` with highlight.js over the restricted subset.
    /// Returns nil if the engine is unavailable (callers fall back to
    /// permissive behavior).
    func detectLanguage(_ text: String) -> LanguageGuess? {
        lock.lock()
        defer { lock.unlock() }
        guard let context = loadedContext(),
              let hljs = context.objectForKeyedSubscript("hljs"),
              !hljs.isUndefined else { return nil }

        context.exception = nil
        guard let result = hljs.invokeMethod(
            "highlightAuto",
            withArguments: [text, Self.detectionSubset]
        ), context.exception == nil else { return nil }

        let language = result.objectForKeyedSubscript("language")
        let second = result.objectForKeyedSubscript("secondBest")
        return LanguageGuess(
            language: language?.isString == true ? language?.toString() : nil,
            relevance: result.objectForKeyedSubscript("relevance")?.toDouble() ?? 0,
            secondLanguage: second?.objectForKeyedSubscript("language")?.isString == true
                ? second?.objectForKeyedSubscript("language")?.toString() : nil,
            secondRelevance: second?.objectForKeyedSubscript("relevance")?.toDouble() ?? 0
        )
    }

    /// Formats `sql` with sql-formatter. Returns nil when the text does not
    /// parse as SQL (sql-formatter throws) or the engine is unavailable.
    func formatSQL(
        _ sql: String,
        dialect: SQLDialect = .postgresql,
        indentation: IndentationStyle = .twoSpaces
    ) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let context = loadedContext(),
              let formatter = context.objectForKeyedSubscript("sqlFormatter"),
              !formatter.isUndefined else { return nil }

        let options: [String: Any] = [
            "language": dialect.rawValue,
            "keywordCase": "upper",
            "tabWidth": indentation == .fourSpaces ? 4 : 2,
            "useTabs": indentation == .tabs
        ]
        context.exception = nil
        guard let result = formatter.invokeMethod("format", withArguments: [sql, options]),
              context.exception == nil,
              result.isString else { return nil }
        return result.toString()
    }

    /// True when node-sql-parser's grammar accepts the text as a SQL
    /// statement (tried against PostgreSQL, then MySQL). This is a real AST
    /// parser: English prose that merely contains SQL keywords is rejected.
    func parsesAsSQL(_ sql: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let context = loadedContext(),
              let parserClass = context.objectForKeyedSubscript("Parser"),
              !parserClass.isUndefined,
              let parser = parserClass.construct(withArguments: []) else { return false }

        for database in ["postgresql", "mysql"] {
            context.exception = nil
            parser.invokeMethod("astify", withArguments: [sql, ["database": database]])
            if context.exception == nil { return true }
        }
        return false
    }
}
