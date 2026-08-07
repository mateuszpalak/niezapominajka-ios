import XCTest
@testable import Reminder

final class CommandInterpreterTests: XCTestCase {

    func testParseReminderResponse() throws {
        let payload = """
        {"content":[{"type":"text","text":"{\\"action\\":\\"reminder\\",\\"title\\":\\"Zadzwonić do mamy\\",\\"dueDate\\":\\"2026-08-07T20:00:00+02:00\\",\\"notes\\":null,\\"confirmation\\":\\"OK, przypomnę Ci o 20:00, żeby zadzwonić do mamy.\\"}"}]}
        """
        let command = try CommandInterpreter.parse(responseData: Data(payload.utf8))
        XCTAssertEqual(command.action, .reminder)
        XCTAssertEqual(command.title, "Zadzwonić do mamy")
        XCTAssertNotNil(command.dueDateParsed)
        XCTAssertNil(command.notes)
        XCTAssertFalse(command.confirmation.isEmpty)
    }

    func testParseNoteWithoutDate() throws {
        let payload = """
        {"content":[{"type":"text","text":"{\\"action\\":\\"note\\",\\"title\\":\\"Pomysł na prezent\\",\\"dueDate\\":null,\\"notes\\":\\"Kupić książkę o górach\\",\\"confirmation\\":\\"Zapisałem notatkę.\\"}"}]}
        """
        let command = try CommandInterpreter.parse(responseData: Data(payload.utf8))
        XCTAssertEqual(command.action, .note)
        XCTAssertNil(command.dueDateParsed)
        XCTAssertEqual(command.notes, "Kupić książkę o górach")
    }

    func testParseShoppingItems() throws {
        let payload = """
        {"content":[{"type":"text","text":"{\\"action\\":\\"shopping\\",\\"title\\":\\"Zakupy\\",\\"dueDate\\":null,\\"notes\\":null,\\"items\\":[\\"Mleko\\",\\"Chleb\\"],\\"confirmation\\":\\"Dodałem mleko i chleb do listy zakupów.\\"}"}]}
        """
        let command = try CommandInterpreter.parse(responseData: Data(payload.utf8))
        XCTAssertEqual(command.action, .shopping)
        XCTAssertEqual(command.items, ["Mleko", "Chleb"])
    }

    func testParseMalformedResponseThrows() {
        let payload = #"{"content":[{"type":"text","text":"to nie jest json"}]}"#
        XCTAssertThrowsError(try CommandInterpreter.parse(responseData: Data(payload.utf8)))
    }

    func testSystemPromptContainsCurrentDateAndTimezone() {
        let prompt = CommandInterpreter.systemPrompt(
            now: Date(timeIntervalSince1970: 1_770_000_000),
            timeZone: TimeZone(identifier: "Europe/Warsaw")!)
        XCTAssertTrue(prompt.contains("Europe/Warsaw"))
        XCTAssertTrue(prompt.contains("2026"))
    }
}
