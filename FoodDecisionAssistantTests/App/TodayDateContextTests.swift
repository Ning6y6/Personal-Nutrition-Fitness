import FoodDecisionCore
import Foundation
import Testing
@testable import FoodDecisionAssistant

@MainActor
struct TodayDateContextTests {
    @Test("An injected midnight wake refreshes the day without changing any meals")
    func midnightRefreshesWindow() async throws {
        let start = try date("2026-10-04T22:59:59Z")
        let midnight = try date("2026-10-04T23:00:00Z")
        var now = start
        let calendar = try londonCalendar()
        var requestedSleep: Duration?
        let context = TodayDateContext(
            now: { now }, calendar: { calendar },
            sleep: { delay in requestedSleep = delay; now = midnight }
        )
        let oldWindow = try #require(context.dayWindow)
        try await context.waitForNextDay()
        let newWindow = try #require(context.dayWindow)
        #expect(requestedSleep == .seconds(1))
        #expect(oldWindow.end == midnight)
        #expect(newWindow.start == midnight)
        #expect(context.refreshRevision == 1)
    }

    @Test("Foreground or clock refresh supports moving forwards and backwards")
    func manualRefreshRecomputesDay() throws {
        var now = try date("2026-10-04T12:00:00Z")
        let calendar = try londonCalendar()
        let context = TodayDateContext(now: { now }, calendar: { calendar })
        let initial = try #require(context.dayWindow)
        now = try date("2026-10-05T12:00:00Z")
        context.refresh()
        #expect(context.dayWindow != initial)
        now = try date("2026-10-04T12:00:00Z")
        context.refresh()
        #expect(context.dayWindow == initial)
        #expect(context.refreshRevision == 2)
    }

    @Test("A same-day clock change reschedules the midnight wait")
    func sameDayChangeReschedules() throws {
        var now = try date("2026-10-04T12:00:00Z")
        let calendar = try londonCalendar()
        let context = TodayDateContext(now: { now }, calendar: { calendar })
        let initial = context.dayWindow
        now = try date("2026-10-04T13:00:00Z")
        context.refresh()
        #expect(context.dayWindow == initial)
        #expect(context.refreshRevision == 1)
    }

    @Test("A timezone change recalculates boundaries for the same instant")
    func timezoneChangeRefreshesWindow() throws {
        let now = try date("2026-10-04T23:30:00Z")
        var calendar = try londonCalendar()
        let context = TodayDateContext(now: { now }, calendar: { calendar })
        let london = try #require(context.dayWindow)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        context.refresh()
        let newYork = try #require(context.dayWindow)
        #expect(newYork != london)
        #expect(newYork.timeZoneIdentifier == "America/New_York")
        #expect(newYork.contains(now))
    }

    @Test("A cancelled wake must not publish a new date")
    func cancellationDoesNotPublish() async throws {
        let now = try date("2026-10-04T12:00:00Z")
        let calendar = try londonCalendar()
        let context = TodayDateContext(
            now: { now }, calendar: { calendar }, sleep: { _ in throw CancellationError() }
        )
        let initial = context.dayWindow
        await #expect(throws: CancellationError.self) { try await context.waitForNextDay() }
        #expect(context.dayWindow == initial)
        #expect(context.refreshRevision == 0)
    }

    @Test("Cancellation after a sleeper returns still prevents a stale date publication")
    func cancellationAfterSuspensionDoesNotPublish() async throws {
        let now = try date("2026-10-04T12:00:00Z")
        let calendar = try londonCalendar()
        let (started, signalStarted) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let (resume, signalResume) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        defer { signalStarted.finish(); signalResume.finish() }
        let context = TodayDateContext(now: { now }, calendar: { calendar }, sleep: { _ in
            signalStarted.yield(())
            for await _ in resume { break }
        })
        let initial = context.dayWindow
        let task = Task { try await context.waitForNextDay() }
        defer { task.cancel() }
        for await _ in started { break }
        task.cancel()
        signalResume.yield(())
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(context.dayWindow == initial)
        #expect(context.refreshRevision == 0)
    }

    @Test("Reappearing views refresh a changed day but do not endlessly restart an unchanged task")
    func refreshIfNeededDoesNotRestartSameDay() throws {
        var now = try date("2026-10-04T12:00:00Z")
        let calendar = try londonCalendar()
        let context = TodayDateContext(now: { now }, calendar: { calendar })
        context.refreshIfNeeded()
        #expect(context.refreshRevision == 0)
        now = try date("2026-10-05T12:00:00Z")
        context.refreshIfNeeded()
        #expect(context.refreshRevision == 1)
        context.refreshIfNeeded()
        #expect(context.refreshRevision == 1)
    }

    @Test("Refresh failures hide the date summary until a valid refresh")
    func failureDoesNotBecomeAnEmptyDay() throws {
        let now = try date("2026-10-04T12:00:00Z")
        let calendar = try londonCalendar()
        let context = TodayDateContext(now: { now }, calendar: { calendar })
        context.markUnavailable()
        #expect(context.dayWindow == nil)
        #expect(context.hasRefreshFailure)
        let failureRevision = context.refreshRevision
        context.refreshIfNeeded()
        #expect(context.dayWindow == nil)
        #expect(context.refreshRevision == failureRevision)
        context.refresh()
        #expect(context.dayWindow != nil)
        #expect(context.hasRefreshFailure == false)
    }

    @Test("Invalid time is unavailable, never interpreted as an empty day")
    func invalidClockIsUnavailable() async throws {
        var now = Date(timeIntervalSince1970: .nan)
        let calendar = try londonCalendar()
        let context = TodayDateContext(now: { now }, calendar: { calendar })
        #expect(context.dayWindow == nil)
        now = try date("2026-10-04T12:00:00Z")
        context.refresh()
        #expect(context.dayWindow != nil)
        now = Date(timeIntervalSince1970: .infinity)
        try await context.waitForNextDay()
        #expect(context.dayWindow == nil)
        #expect(context.hasRefreshFailure)
        context.refreshIfNeeded()
        #expect(context.dayWindow == nil)
        now = try date("2026-10-04T12:00:00Z")
        context.refresh()
        #expect(context.dayWindow != nil)
        #expect(context.hasRefreshFailure == false)
    }

    private func date(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }

    private func londonCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/London"))
        return calendar
    }
}
