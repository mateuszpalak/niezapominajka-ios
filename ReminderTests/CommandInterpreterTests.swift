import XCTest
@testable import Reminder

final class CommandInterpreterTests: XCTestCase {

    func testParseReminderResponse() throws {
        let payload = """
        {"content":[{"type":"text","text":"{\\"action\\":\\"reminder\\",\\"title\\":\\"Zadzwonić do mamy\\",\\"dueDate\\":\\"2026-08-07T20:00:00+02:00\\",\\"notes\\":null,\\"confirmation\\":\\"OK, przypomnę Ci o 20:00, żeby zadzwonić do mamy.\\"}"}]}
        """
        let command = try XCTUnwrap(CommandInterpreter.parse(responseData: Data(payload.utf8)).first)
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
        let command = try XCTUnwrap(CommandInterpreter.parse(responseData: Data(payload.utf8)).first)
        XCTAssertEqual(command.action, .note)
        XCTAssertNil(command.dueDateParsed)
        XCTAssertEqual(command.notes, "Kupić książkę o górach")
    }

    func testParseShoppingItems() throws {
        let payload = """
        {"content":[{"type":"text","text":"{\\"action\\":\\"shopping\\",\\"title\\":\\"Zakupy\\",\\"dueDate\\":null,\\"notes\\":null,\\"items\\":[\\"Mleko\\",\\"Chleb\\"],\\"confirmation\\":\\"Dodałem mleko i chleb do listy zakupów.\\"}"}]}
        """
        let command = try XCTUnwrap(CommandInterpreter.parse(responseData: Data(payload.utf8)).first)
        XCTAssertEqual(command.action, .shopping)
        XCTAssertEqual(command.items, ["Mleko", "Chleb"])
    }

    func testParseMultipleActions() throws {
        let payload = """
        {"content":[{"type":"text","text":"{\\"actions\\":[{\\"action\\":\\"shopping\\",\\"title\\":\\"Zakupy\\",\\"dueDate\\":null,\\"endDate\\":null,\\"notes\\":null,\\"items\\":[\\"Mleko\\",\\"Masło\\"],\\"location\\":null,\\"recipient\\":null,\\"clarify\\":null,\\"confirmation\\":\\"Dodałem.\\"},{\\"action\\":\\"reminder\\",\\"title\\":\\"Wziąć tabletkę\\",\\"dueDate\\":\\"2026-10-20T20:00:00+02:00\\",\\"endDate\\":null,\\"notes\\":null,\\"items\\":null,\\"location\\":null,\\"recipient\\":null,\\"clarify\\":null,\\"confirmation\\":\\"Przypomnę.\\"}]}"}]}
        """
        let commands = try CommandInterpreter.parse(responseData: Data(payload.utf8))
        XCTAssertEqual(commands.map(\.action), [.shopping, .reminder])
        XCTAssertEqual(commands[0].items, ["Mleko", "Masło"])
        XCTAssertEqual(commands[1].title, "Wziąć tabletkę")
        XCTAssertNotNil(commands[1].dueDateParsed)
    }

    func testParseMessageWithClarify() throws {
        let payload = """
        {"content":[{"type":"text","text":"{\\"actions\\":[{\\"action\\":\\"message\\",\\"title\\":\\"SMS do Ani\\",\\"dueDate\\":null,\\"endDate\\":null,\\"notes\\":\\"Cześć, spóźnię się około 10 minut.\\",\\"items\\":null,\\"location\\":null,\\"recipient\\":\\"Ania\\",\\"clarify\\":\\"Do której Ani wysłać?\\",\\"confirmation\\":\\"Wysyłam.\\"}]}"}]}
        """
        let command = try XCTUnwrap(CommandInterpreter.parse(responseData: Data(payload.utf8)).first)
        XCTAssertEqual(command.action, .message)
        XCTAssertEqual(command.recipient, "Ania")
        XCTAssertEqual(command.clarify, "Do której Ani wysłać?")
    }

    func testShoppingCardTitleListsItems() {
        let shopping = PlannedAction(command: InterpretedCommand(
            action: .shopping, title: "Zakupy", items: ["Mleko", "Masło", "Chleb"], confirmation: "OK", listName: "Zakupy"))
        XCTAssertEqual(shopping.cardTitle, "Mleko, Masło, Chleb")
    }

    func testEventFieldsAndDateEditingKeepsDuration() throws {
        var event = PlannedAction(command: InterpretedCommand(
            action: .event, title: "Spotkanie z Markiem", dueDate: "2026-10-23T12:00:00+02:00",
            endDate: "2026-10-23T13:00:00+02:00", location: "Biuro", confirmation: "OK", calendarName: "Praca"))
        XCTAssertEqual(event.fields().map(\.label), ["Tytuł", "Kiedy", "Miejsce", "Kalendarz"])
        let newStart = try XCTUnwrap(InterpretedCommand.parseDate("2026-10-23T14:00:00+02:00"))
        event.setDate(newStart)
        XCTAssertEqual(event.command.endDateParsed?.timeIntervalSince(newStart), 3600)
    }

    func testContactMasking() {
        XCTAssertEqual(ContactMatch.mask("+48 512 345 204"), "512 *** 204")
        let match = ContactMatch(id: "1", name: "Ania Kowalska",
                                 numbers: [.init(label: "komórka", value: "512345204")])
        XCTAssertEqual(match.initials, "AK")
        XCTAssertEqual(match.subtitle, "komórka · 512 *** 204")
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
