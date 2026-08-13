import XCTest
@testable import BracePaste

final class SQLFormatterDetectionTests: XCTestCase {
    func testSelectDetected() {
        XCTAssertTrue(SQLFormatter.isLikelySQL("select * from users where id = 1"))
        XCTAssertTrue(SQLFormatter.isLikelySQL("SELECT name from users"))
        XCTAssertTrue(SQLFormatter.isLikelySQL("select id, name from users;"))
    }

    func testInsertUpdateDeleteDetected() {
        XCTAssertTrue(SQLFormatter.isLikelySQL(#"insert into t (a) values ('x')"#))
        XCTAssertTrue(SQLFormatter.isLikelySQL("update users set name = 'a' where id = 1"))
        XCTAssertTrue(SQLFormatter.isLikelySQL("delete from users where id = 1"))
        XCTAssertTrue(SQLFormatter.isLikelySQL("with cte as (select 1) select * from cte"))
    }

    func testLeadingCommentsSkipped() {
        XCTAssertTrue(SQLFormatter.isLikelySQL("-- fetch users\nselect * from users"))
        XCTAssertTrue(SQLFormatter.isLikelySQL("/* comment */ select * from users"))
    }

    func testEnglishSentenceRejected() {
        XCTAssertFalse(SQLFormatter.isLikelySQL("Select the best option from the list"))
        XCTAssertFalse(SQLFormatter.isLikelySQL("Update your profile so we know where to reach you"))
        XCTAssertFalse(SQLFormatter.isLikelySQL("Delete old files from the folder"))
        XCTAssertFalse(SQLFormatter.isLikelySQL("create something amazing"))
    }

    func testJSONAndLogsRejected() {
        XCTAssertFalse(SQLFormatter.isLikelySQL(#"{"a":1}"#))
        XCTAssertFalse(SQLFormatter.isLikelySQL(#"Agent result: payload={"status":"ok"} done"#))
        XCTAssertFalse(SQLFormatter.isLikelySQL("This is not SQL."))
        XCTAssertFalse(SQLFormatter.isLikelySQL(""))
    }
}

final class SQLFormatterFormattingTests: XCTestCase {
    func testClauseBreaksAndKeywordCase() {
        let formatted = SQLFormatter.format("select id, name from users where active = true and age > 21 order by name")
        let lines = formatted.split(separator: "\n").map(String.init)
        XCTAssertTrue(lines[0].hasPrefix("SELECT"))
        XCTAssertTrue(lines.contains { $0.hasPrefix("FROM users") })
        XCTAssertTrue(lines.contains { $0.hasPrefix("WHERE active = TRUE") })
        XCTAssertTrue(lines.contains { $0.contains("AND age > 21") })
        XCTAssertTrue(lines.contains { $0.hasPrefix("ORDER BY") })
    }

    func testSelectListOneItemPerLine() {
        let formatted = SQLFormatter.format("select id, name, email from users")
        XCTAssertTrue(formatted.contains("SELECT id,\n"))
        XCTAssertTrue(formatted.contains("name,\n"))
    }

    func testFunctionCallsKeepNoSpaceAndInlineCommas() {
        let formatted = SQLFormatter.format("select coalesce(a, b) from t")
        XCTAssertTrue(formatted.contains("COALESCE(a, b)"))
    }

    func testEmbeddedJSONPrettyPrintedInPlace() {
        let sql = #"insert into events (payload) values ('{"type":"click","count":3}')"#
        let formatted = SQLFormatter.format(sql)
        XCTAssertTrue(formatted.contains("INSERT INTO events"))
        XCTAssertTrue(formatted.contains("\"type\""))
        // JSON is multi-line inside the quotes
        XCTAssertTrue(formatted.contains("{\n"))
        XCTAssertTrue(formatted.hasSuffix("')"))
    }

    func testEmbeddedJSONWithEscapedSingleQuotes() {
        let sql = #"update t set data = '{"note":"it''s fine"}' where id = 1"#
        let formatted = SQLFormatter.format(sql)
        XCTAssertTrue(formatted.contains("it''s fine"))
        let minified = SQLFormatter.minify(formatted)
        XCTAssertTrue(minified.contains(#"{"note":"it''s fine"}"#))
    }

    func testNonJSONStringsUntouched() {
        let formatted = SQLFormatter.format("select * from t where name = 'O''Brien'")
        XCTAssertTrue(formatted.contains("'O''Brien'"))
    }

    func testJSONOperatorsAndCasts() {
        let formatted = SQLFormatter.format(#"select * from t where data @> '{"a":1}'::jsonb"#)
        XCTAssertTrue(formatted.contains("@>"))
        XCTAssertTrue(formatted.contains("'::jsonb"))
    }

    func testIdempotent() {
        let sql = #"select id, data from events where data @> '{"a":{"b":[1,2]}}' and active = true order by id"#
        let once = SQLFormatter.format(sql)
        let twice = SQLFormatter.format(once)
        XCTAssertEqual(once, twice)
    }

    func testMinifyCollapsesToOneLine() {
        let sql = #"insert into events (payload) values ('{"type":"click"}')"#
        let formatted = SQLFormatter.format(sql)
        let minified = SQLFormatter.minify(formatted)
        XCTAssertFalse(minified.contains("\n"))
        XCTAssertTrue(minified.contains(#"'{"type":"click"}'"#))
    }

    func testLineCommentStaysOnOwnLine() {
        let formatted = SQLFormatter.format("select a -- the id\nfrom t")
        XCTAssertTrue(formatted.contains("-- the id"))
        XCTAssertTrue(formatted.contains("\nFROM t"))
    }
}

final class SQLExtractionIntegrationTests: XCTestCase {
    func testSQLWithEmbeddedJSONFormatsWholeQuery() {
        let input = #"UPDATE apps SET config = '{"moderation":{"enabled":true}}' WHERE id = 42;"#
        let result = JSONExtractor.process(input)
        let success = try! XCTUnwrap(result.success)
        XCTAssertEqual(success.source, .sql)
        XCTAssertTrue(success.formattedJSON.contains("UPDATE apps"))
        XCTAssertTrue(success.formattedJSON.contains("WHERE id = 42"))
        XCTAssertTrue(success.formattedJSON.contains("\"moderation\""))
    }

    func testSQLWithoutJSONStillFormats() {
        let input = "select id, name from users where active = true"
        let result = JSONExtractor.process(input)
        XCTAssertEqual(result.success?.source, .sql)
        XCTAssertTrue(result.success?.formattedJSON.contains("FROM users") == true)
    }

    func testLogNoiseStillStripsToJSON() {
        let input = #"Agent result: payload={"status":"ok","count":3} completed successfully"#
        let result = JSONExtractor.process(input)
        XCTAssertEqual(result.success?.source, .surroundingText)
    }

    func testExactJSONStillWinsOverSQLDetection() {
        let input = #"{"query":"select * from users"}"#
        let result = JSONExtractor.process(input)
        XCTAssertEqual(result.success?.source, .exact)
    }

    func testEnglishSentenceStillFails() {
        let result = JSONExtractor.process("Select the best option from the list")
        XCTAssertFalse(result.isSuccess)
    }
}
