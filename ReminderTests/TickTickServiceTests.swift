import XCTest
@testable import Reminder

final class TickTickServiceTests: XCTestCase {
    private let warsaw = TimeZone(identifier: "Europe/Warsaw")!

    func testFormatsDateWithOffsetWithoutColon() throws {
        let date = try XCTUnwrap(InterpretedCommand.parseDate("2026-10-20T15:00:00+02:00"))
        XCTAssertEqual(TickTickService.formatDate(date, timeZone: warsaw), "2026-10-20T15:00:00+0200")
    }

    func testParsesResponseDatesWithAndWithoutMilliseconds() throws {
        let expected = try XCTUnwrap(InterpretedCommand.parseDate("2026-10-20T15:00:00+02:00"))
        XCTAssertEqual(TickTickService.parseDate("2026-10-20T13:00:00.000+0000"), expected)
        XCTAssertEqual(TickTickService.parseDate("2026-10-20T13:00:00+0000"), expected)
        XCTAssertNil(TickTickService.parseDate(nil))
    }

    func testTaskBodyWithDueDateSetsReminderAtDueTime() throws {
        let date = try XCTUnwrap(InterpretedCommand.parseDate("2026-10-20T15:00:00+02:00"))
        let body = TickTickService.taskBody(title: "Zadzwonić do mamy", notes: "", dueDate: date,
                                            projectID: "inbox", timeZone: warsaw)
        XCTAssertEqual(body["title"] as? String, "Zadzwonić do mamy")
        XCTAssertEqual(body["projectId"] as? String, "inbox")
        XCTAssertEqual(body["dueDate"] as? String, "2026-10-20T15:00:00+0200")
        XCTAssertEqual(body["startDate"] as? String, "2026-10-20T15:00:00+0200")
        XCTAssertEqual(body["timeZone"] as? String, "Europe/Warsaw")
        XCTAssertEqual(body["reminders"] as? [String], ["TRIGGER:PT0S"])
        XCTAssertNil(body["content"], "pusta notatka nie trafia do TickTick")
    }

    func testNoteBodyHasNoDate() {
        let body = TickTickService.taskBody(title: "Pomysł", notes: "Książka o górach", dueDate: nil,
                                            projectID: "p1", kind: "NOTE")
        XCTAssertEqual(body["kind"] as? String, "NOTE")
        XCTAssertEqual(body["content"] as? String, "Książka o górach")
        XCTAssertNil(body["dueDate"])
        XCTAssertNil(body["reminders"])
    }

    func testMatcherFindsTaskBySharedWord() {
        let tasks = [
            TaskSummary(ref: .ticktick(project: "p", task: "1"), title: "Zadzwonić do mamy", dueDate: nil, hasTime: false),
            TaskSummary(ref: .ticktick(project: "p", task: "2"), title: "Mleko", dueDate: nil, hasTime: false),
        ]
        XCTAssertEqual(TaskMatcher.bestMatch(for: "mleko", in: tasks)?.ref, .ticktick(project: "p", task: "2"))
        XCTAssertEqual(TaskMatcher.bestMatch(for: "zadzwonić do mamy", in: tasks)?.title, "Zadzwonić do mamy")
        XCTAssertNil(TaskMatcher.bestMatch(for: "chleb", in: tasks))
    }

    func testDetectsShoppingList() {
        XCTAssertEqual(TaskMatcher.shoppingList(in: ["💙PRIV - General", "💙PRIV - Shopping"]), "💙PRIV - Shopping")
        XCTAssertEqual(TaskMatcher.shoppingList(in: ["Dom", "Zakupy"]), "Zakupy")
        XCTAssertNil(TaskMatcher.shoppingList(in: ["Dom"]))
    }
}
