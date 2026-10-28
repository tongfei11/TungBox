import Foundation
import XCTest
@testable import TungBox

final class RuleSetURLPreferencesTests: XCTestCase {
    func testExplicitDefaultOverridesSubscriptionAndClearingRestoresFallback() throws {
        let suite = "TungBox.RuleSetURLPreferencesTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let tag = TungBoxConfig.ruleSetCN
        let builtIn = try XCTUnwrap(TungBoxConfig.defaultRuleSetURLs[tag])
        let subscription = "https://example.com/subscription.srs"

        XCTAssertEqual(TungBoxConfig.ruleSetURLOverride(for: tag, defaults: defaults), "")
        XCTAssertEqual(TungBoxConfig.resolvedRuleSetURL(for: tag, subscriptionURLs: [tag: subscription], defaults: defaults), subscription)

        TungBoxConfig.setRuleSetURL(builtIn, for: tag, defaults: defaults)
        let reloaded = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertEqual(TungBoxConfig.ruleSetURLOverride(for: tag, defaults: reloaded), builtIn)
        XCTAssertEqual(TungBoxConfig.resolvedRuleSetURL(for: tag, subscriptionURLs: [tag: subscription], defaults: reloaded), builtIn)

        TungBoxConfig.setRuleSetURL("", for: tag, defaults: reloaded)
        XCTAssertEqual(TungBoxConfig.resolvedRuleSetURL(for: tag, subscriptionURLs: [tag: subscription], defaults: reloaded), subscription)
        XCTAssertEqual(TungBoxConfig.resolvedRuleSetURL(for: tag, subscriptionURLs: [:], defaults: reloaded), builtIn)
    }
}
