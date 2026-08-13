import XCTest
@testable import BracePaste

final class SQLFormatterDetectionTests: XCTestCase {
    func testRealQueriesDetected() {
        XCTAssertTrue(SQLFormatter.isLikelySQL("select * from users where id = 1"))
        XCTAssertTrue(SQLFormatter.isLikelySQL("select name from users"))
        XCTAssertTrue(SQLFormatter.isLikelySQL(#"insert into t (a) values ('x')"#))
        XCTAssertTrue(SQLFormatter.isLikelySQL("update users set name = 'a' where id = 1"))
        XCTAssertTrue(SQLFormatter.isLikelySQL("delete from moderation_flags where app_pk = 42"))
        XCTAssertTrue(SQLFormatter.isLikelySQL("with cte as (select 1) select * from cte"))
        XCTAssertTrue(SQLFormatter.isLikelySQL("create table t (id int primary key, data jsonb)"))
    }

    func testPostgresOperatorsDetected() {
        XCTAssertTrue(SQLFormatter.isLikelySQL(
            #"SELECT id FROM core_site WHERE config @> '{"a":1}'::jsonb LIMIT 5;"#
        ))
    }

    func testQueriesWithStopwordsInStringsDetected() {
        XCTAssertTrue(SQLFormatter.isLikelySQL("select * from books where title = 'The Trial'"))
    }

    func testLeadingCommentsSkipped() {
        XCTAssertTrue(SQLFormatter.isLikelySQL("-- fetch users\nselect * from users"))
        XCTAssertTrue(SQLFormatter.isLikelySQL("/* comment */ select * from users"))
    }

    func testEnglishProseRejectedByGrammar() {
        XCTAssertFalse(SQLFormatter.isLikelySQL("Select the best option from the list below and let me know"))
        XCTAssertFalse(SQLFormatter.isLikelySQL("Update your profile so we know where to reach you"))
        XCTAssertFalse(SQLFormatter.isLikelySQL("Create a table from the data in the spreadsheet"))
        XCTAssertFalse(SQLFormatter.isLikelySQL(
            "Show HN: BracePaste – Format JSON/SQL from the clipboard with double Cmd-C (macOS)"
        ))
    }

    func testSourceCodeRejected() {
        XCTAssertFalse(SQLFormatter.isLikelySQL(
            "func (f *floodConditionBase) detectRequest(app *types.ApplicationConfig, userID string, mediaIdentities []string) labelsflood.Request {"
        ))
        XCTAssertFalse(SQLFormatter.isLikelySQL(#"{"a":1}"#))
        XCTAssertFalse(SQLFormatter.isLikelySQL("This is not SQL."))
        XCTAssertFalse(SQLFormatter.isLikelySQL(""))
    }
}

final class SQLFormatterFormattingTests: XCTestCase {
    func testClausesOnOwnLinesAndKeywordsUppercased() {
        let formatted = SQLFormatter.format("select id, name from users where active = true and age > 21 order by name")
        let output = try! XCTUnwrap(formatted)
        XCTAssertTrue(output.hasPrefix("SELECT"))
        XCTAssertTrue(output.contains("\nFROM"))
        XCTAssertTrue(output.contains("\nWHERE"))
        XCTAssertTrue(output.contains("AND age > 21"))
        XCTAssertTrue(output.contains("ORDER BY"))
    }

    func testEmbeddedJSONPrettyPrintedInPlace() {
        let sql = #"insert into events (payload) values ('{"type":"click","count":3}')"#
        let formatted = try! XCTUnwrap(SQLFormatter.format(sql))
        XCTAssertTrue(formatted.contains("INSERT INTO"))
        XCTAssertTrue(formatted.contains("\"type\""))
        XCTAssertTrue(formatted.contains("{\n"))
    }

    func testEmbeddedJSONWithEscapedSingleQuotes() {
        let sql = #"update t set data = '{"note":"it''s fine"}' where id = 1"#
        let formatted = try! XCTUnwrap(SQLFormatter.format(sql))
        XCTAssertTrue(formatted.contains("it''s fine"))
        let minified = SQLFormatter.minify(formatted)
        XCTAssertTrue(minified.contains(#"{"note":"it''s fine"}"#))
    }

    func testNonJSONStringsUntouched() {
        let formatted = try! XCTUnwrap(SQLFormatter.format("select * from t where name = 'O''Brien'"))
        XCTAssertTrue(formatted.contains("'O''Brien'"))
    }

    func testJSONOperatorsAndCasts() {
        let formatted = try! XCTUnwrap(SQLFormatter.format(#"select * from t where data @> '{"a":1}'::jsonb"#))
        XCTAssertTrue(formatted.contains("@>"))
        XCTAssertTrue(formatted.contains("::jsonb"))
    }

    func testIdempotent() {
        let sql = #"select id, data from events where data @> '{"a":{"b":[1,2]}}' and active = true order by id"#
        let once = try! XCTUnwrap(SQLFormatter.format(sql))
        let twice = try! XCTUnwrap(SQLFormatter.format(once))
        XCTAssertEqual(once, twice)
    }

    func testMinifyCollapsesToOneLine() {
        let sql = #"insert into events (payload) values ('{"type":"click"}')"#
        let formatted = try! XCTUnwrap(SQLFormatter.format(sql))
        let minified = SQLFormatter.minify(formatted)
        XCTAssertFalse(minified.contains("\n"))
        XCTAssertTrue(minified.contains(#"'{"type":"click"}'"#))
    }
}

final class SQLExtractionIntegrationTests: XCTestCase {
    func testSQLWithEmbeddedJSONFormatsWholeQuery() {
        let input = #"UPDATE apps SET config = '{"moderation":{"enabled":true}}' WHERE id = 42;"#
        let result = JSONExtractor.process(input)
        let success = try! XCTUnwrap(result.success)
        XCTAssertEqual(success.source, .sql)
        XCTAssertTrue(success.formattedJSON.contains("UPDATE"))
        XCTAssertTrue(success.formattedJSON.contains("\"moderation\""))
    }

    func testSQLWithoutJSONStillFormats() {
        let input = "select id, name from users where active = true"
        let result = JSONExtractor.process(input)
        XCTAssertEqual(result.success?.source, .sql)
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
        let result = JSONExtractor.process("Select the best option from the list below and let me know")
        XCTAssertFalse(result.isSuccess)
    }
}

final class CodeFragmentExtractionTests: XCTestCase {
    func testGoFunctionSignatureIgnored() {
        let input = "func (f *floodConditionBase) detectRequest(app *types.ApplicationConfig, userID, ruleID, content string, mediaIdentities []string) labelsflood.Request {"
        XCTAssertFalse(JSONExtractor.process(input).isSuccess)
    }

    func testArrayIndexingIgnored() {
        XCTAssertFalse(JSONExtractor.process("value := items[0] + items[1]").isSuccess)
    }

    func testEmptyContainersInProseIgnored() {
        XCTAssertFalse(JSONExtractor.process("initialized state {} and queue [] flushed").isSuccess)
    }

    func testGoSnippetWithKeylessArrayIgnored() {
        let input = """
        func main() {
            ids := []int{}
            fmt.Println(len(ids))
        }
        """
        XCTAssertFalse(JSONExtractor.process(input).isSuccess)
    }

    func testExactEmptyContainersStillFormat() {
        XCTAssertTrue(JSONExtractor.process("{}").isSuccess)
        XCTAssertTrue(JSONExtractor.process("[]").isSuccess)
    }

    func testMultiElementArrayInProseStillExtracted() {
        let result = JSONExtractor.process("scores=[1,2,3] recorded")
        XCTAssertEqual(result.success?.source, .surroundingText)
    }

    func testCodeWithRealJSONPayloadStillExtracted() {
        let input = #"logger.Info("resp", `{"status":"ok","count":3}`)"#
        let result = JSONExtractor.process(input)
        XCTAssertEqual(result.success?.source, .surroundingText)
    }
}
