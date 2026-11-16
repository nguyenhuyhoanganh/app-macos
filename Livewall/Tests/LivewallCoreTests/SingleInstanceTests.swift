import Foundation
import Testing
@testable import LivewallCore

struct SingleInstanceTests {
    private let first = Date(timeIntervalSince1970: 100)
    private let second = Date(timeIntervalSince1970: 200)
    private let third = Date(timeIntervalSince1970: 300)

    @Test func aLoneProcessKeepsRunning() {
        #expect(SingleInstance.earlierInstance(launchDates: [10: first], current: 10) == nil)
    }

    @Test func aSecondProcessYieldsToTheOneAlreadyRunning() {
        #expect(SingleInstance.earlierInstance(launchDates: [10: first, 20: second], current: 20) == 10)
    }

    @Test func theFirstProcessDoesNotYieldToALaterOne() {
        #expect(SingleInstance.earlierInstance(launchDates: [10: first, 20: second], current: 10) == nil)
    }

    @Test func withSeveralRunningItYieldsToTheOldest() {
        let dates = [30: third, 10: first, 20: second]
        #expect(SingleInstance.earlierInstance(launchDates: dates, current: 30) == 10)
    }

    @Test func launchTimeDecidesEvenWhenProcessIDsHaveWrappedAround() {
        let dates = [99_000: first, 200: second]
        #expect(SingleInstance.earlierInstance(launchDates: dates, current: 200) == 99_000)
        #expect(SingleInstance.earlierInstance(launchDates: dates, current: 99_000) == nil)
    }
}
