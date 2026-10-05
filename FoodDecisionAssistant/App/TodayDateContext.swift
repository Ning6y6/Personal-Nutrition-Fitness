import FoodDecisionCore
import Foundation
import Observation

/// Transient UI date state only. Refreshing never writes, edits or deletes meal data.
/// The injected wall clock/calendar and sleeper make DST, clock changes and cancellation testable.
@Observable
@MainActor
final class TodayDateContext {
    private(set) var dayWindow: MealDayWindow?
    private(set) var refreshRevision: UInt = 0
    private(set) var hasRefreshFailure = false

    private let now: () -> Date
    private let calendar: () -> Calendar
    private let sleep: @MainActor (Duration) async throws -> Void

    init(
        now: @escaping () -> Date = { .now },
        calendar: @escaping () -> Calendar = { .current },
        sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.now = now
        self.calendar = calendar
        self.sleep = sleep
        dayWindow = try? MealDayWindow(containing: now(), calendar: calendar())
    }

    /// Always invalidate the wake schedule: even a same-day wall-clock adjustment changes its delay.
    func refresh() {
        dayWindow = try? MealDayWindow(containing: now(), calendar: calendar())
        hasRefreshFailure = false
        refreshRevision &+= 1
    }

    /// Reappearing views may have retained their state while their boundary task was cancelled.
    func refreshIfNeeded() {
        // A persistent wake failure must not become an unbounded immediate retry loop.
        // Only an explicit foreground/system-event refresh clears this failure state.
        guard !hasRefreshFailure else { return }
        let current = try? MealDayWindow(containing: now(), calendar: calendar())
        guard current != dayWindow else { return }
        dayWindow = current
        refreshRevision &+= 1
    }

    func markUnavailable() {
        dayWindow = nil
        hasRefreshFailure = true
        refreshRevision &+= 1
    }

    /// One wake per local day, not a repeating per-second/minute polling timer.
    /// SwiftUI owns cancellation when inactive, removed, or rescheduled by a system notification.
    func waitForNextDay() async throws {
        try Task.checkCancellation()
        guard let dayWindow else { return }
        let remaining = dayWindow.end.timeIntervalSince(now())
        guard remaining.isFinite else {
            markUnavailable()
            return
        }
        try await sleep(.seconds(max(remaining, 0)))
        try Task.checkCancellation()
        refresh()
    }
}
