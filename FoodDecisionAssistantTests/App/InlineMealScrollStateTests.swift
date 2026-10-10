import Foundation
import Testing

@testable import FoodDecisionAssistant

struct InlineMealScrollStateTests {
    @Test("Layout and animation gates can arrive in either order", arguments: [true, false])
    func gatesMayArriveInEitherOrder(layoutFirst: Bool) throws {
        let mealID = UUID()
        var state = InlineMealScrollState()
        let startedRequest = state.begin(expandedMealID: mealID)
        let request = try #require(startedRequest)

        if layoutFirst {
            state.recordLayout(for: request)
        } else {
            state.completeAnimation(for: request)
        }
        let pendingTarget = state.takeReadyTarget(expandedMealID: mealID, visibleIDs: [mealID], isActive: true)
        #expect(pendingTarget == nil)
        #expect(state.request == request)

        if layoutFirst {
            state.completeAnimation(for: request)
        } else {
            state.recordLayout(for: request)
        }
        let readyTarget = state.takeReadyTarget(expandedMealID: mealID, visibleIDs: [mealID], isActive: true)
        #expect(readyTarget == mealID)
        #expect(state.request == nil)
    }

    @Test("A missing gate retains the pending request without scrolling", arguments: ["none", "layout", "animation"])
    func missingGateDoesNotScroll(completedGate: String) throws {
        let mealID = UUID()
        var state = InlineMealScrollState()
        let startedRequest = state.begin(expandedMealID: mealID)
        let request = try #require(startedRequest)

        if completedGate == "layout" { state.recordLayout(for: request) }
        if completedGate == "animation" { state.completeAnimation(for: request) }

        let target = state.takeReadyTarget(expandedMealID: mealID, visibleIDs: [mealID], isActive: true)
        #expect(target == nil)
        #expect(state.request == request)
    }

    @Test("A ready target is consumed once and late callbacks cannot restore it")
    func readyTargetIsConsumedOnce() throws {
        let mealID = UUID()
        var state = InlineMealScrollState()
        let startedRequest = state.begin(expandedMealID: mealID)
        let request = try #require(startedRequest)
        state.recordLayout(for: request)
        state.completeAnimation(for: request)

        let firstTarget = state.takeReadyTarget(expandedMealID: mealID, visibleIDs: [mealID], isActive: true)
        #expect(firstTarget == mealID)
        state.recordLayout(for: request)
        state.completeAnimation(for: request)
        let laterTarget = state.takeReadyTarget(expandedMealID: mealID, visibleIDs: [mealID], isActive: true)
        #expect(laterTarget == nil)
        #expect(state.request == nil)
    }

    @Test("Every new expansion discards prior readiness", arguments: [true, false])
    func replacementStartsWithFreshGates(sameMeal: Bool) throws {
        let firstMealID = UUID()
        let nextMealID = sameMeal ? firstMealID : UUID()
        var state = InlineMealScrollState()
        let firstRequest = state.begin(expandedMealID: firstMealID)
        let first = try #require(firstRequest)
        state.recordLayout(for: first)
        state.completeAnimation(for: first)

        let nextRequest = state.begin(expandedMealID: nextMealID)
        let next = try #require(nextRequest)
        #expect(next.token != first.token)
        #expect(next.mealID == nextMealID)
        let target = state.takeReadyTarget(expandedMealID: nextMealID, visibleIDs: [nextMealID], isActive: true)
        #expect(target == nil)
        #expect(state.request == next)
    }

    @Test("A → B → A ignores callbacks from both previous expansions")
    func repeatedMealCannotAcceptStaleCallbacks() throws {
        let mealA = UUID()
        let mealB = UUID()
        var state = InlineMealScrollState()
        let firstARequest = state.begin(expandedMealID: mealA)
        let firstA = try #require(firstARequest)
        let previousBRequest = state.begin(expandedMealID: mealB)
        let previousB = try #require(previousBRequest)
        let currentARequest = state.begin(expandedMealID: mealA)
        let currentA = try #require(currentARequest)
        #expect(firstA.token != currentA.token)

        state.recordLayout(for: firstA)
        state.completeAnimation(for: firstA)
        state.recordLayout(for: previousB)
        state.completeAnimation(for: previousB)
        let staleTarget = state.takeReadyTarget(expandedMealID: mealA, visibleIDs: [mealA, mealB], isActive: true)
        #expect(staleTarget == nil)
        #expect(state.request == currentA)

        state.recordLayout(for: currentA)
        state.completeAnimation(for: currentA)
        let currentTarget = state.takeReadyTarget(expandedMealID: mealA, visibleIDs: [mealA, mealB], isActive: true)
        #expect(currentTarget == mealA)
    }

    @Test("Collapsing clears the request and both gates")
    func collapseCannotScroll() throws {
        let mealID = UUID()
        var state = InlineMealScrollState()
        let startedRequest = state.begin(expandedMealID: mealID)
        let request = try #require(startedRequest)
        state.recordLayout(for: request)
        state.completeAnimation(for: request)

        let collapsedRequest = state.begin(expandedMealID: nil)
        #expect(collapsedRequest == nil)
        state.recordLayout(for: request)
        state.completeAnimation(for: request)
        let target = state.takeReadyTarget(expandedMealID: nil, visibleIDs: [mealID], isActive: true)
        #expect(target == nil)
        #expect(state.request == nil)
    }

    @Test("Removal, day changes and inactivity discard a ready request", arguments: ["removed", "changedDay", "inactive"])
    func invalidContextCannotScroll(context: String) throws {
        let mealID = UUID()
        var state = InlineMealScrollState()
        let startedRequest = state.begin(expandedMealID: mealID)
        let request = try #require(startedRequest)
        state.recordLayout(for: request)
        state.completeAnimation(for: request)

        let expandedMealID: UUID? = context == "changedDay" ? nil : mealID
        let visibleIDs = context == "removed" ? [] : [mealID]
        let isActive = context != "inactive"
        let invalidTarget = state.takeReadyTarget(expandedMealID: expandedMealID, visibleIDs: visibleIDs, isActive: isActive)
        #expect(invalidTarget == nil)
        #expect(state.request == nil)

        state.recordLayout(for: request)
        state.completeAnimation(for: request)
        let laterTarget = state.takeReadyTarget(expandedMealID: mealID, visibleIDs: [mealID], isActive: true)
        #expect(laterTarget == nil)
    }

    @Test("Context is invalidated before missing layout or animation gates are checked")
    func invalidContextDoesNotWaitForGates() throws {
        let mealID = UUID()
        var state = InlineMealScrollState()
        let startedRequest = state.begin(expandedMealID: mealID)
        let request = try #require(startedRequest)

        let inactiveTarget = state.takeReadyTarget(expandedMealID: mealID, visibleIDs: [mealID], isActive: false)
        #expect(inactiveTarget == nil)
        #expect(state.request == nil)
        state.recordLayout(for: request)
        state.completeAnimation(for: request)
        let laterTarget = state.takeReadyTarget(expandedMealID: mealID, visibleIDs: [mealID], isActive: true)
        #expect(laterTarget == nil)
    }

    @Test("Explicit invalidation returns the state to its initial value")
    func explicitInvalidationClearsAllState() throws {
        var state = InlineMealScrollState()
        let startedRequest = state.begin(expandedMealID: UUID())
        let request = try #require(startedRequest)
        state.recordLayout(for: request)
        state.completeAnimation(for: request)

        state.invalidate()
        #expect(state == InlineMealScrollState())
    }

    @Test("Callbacks must match the meal as well as the token")
    func mismatchedMealWithCurrentTokenDoesNotUnlockGates() throws {
        let mealID = UUID()
        var state = InlineMealScrollState()
        let startedRequest = state.begin(expandedMealID: mealID)
        let request = try #require(startedRequest)
        let mismatched = InlineMealScrollState.Request(token: request.token, mealID: UUID())

        state.recordLayout(for: mismatched)
        state.completeAnimation(for: mismatched)
        let target = state.takeReadyTarget(expandedMealID: mealID, visibleIDs: [mealID], isActive: true)
        #expect(target == nil)
        #expect(state.request == request)
    }
}
