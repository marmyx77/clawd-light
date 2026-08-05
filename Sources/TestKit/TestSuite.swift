import Foundation

/// A single test case.
public struct TestCase {
    public let name: String
    public let body: (Assertions) -> Void

    public init(_ name: String, _ body: @escaping (Assertions) -> Void) {
        self.name = name
        self.body = body
    }
}

/// A named group of test cases.
public struct TestSuite {
    public let name: String
    public let cases: [TestCase]

    public init(_ name: String, _ cases: [TestCase]) {
        self.name = name
        self.cases = cases
    }
}

/// Outcome of one executed case.
public struct TestOutcome {
    public let suite: String
    public let name: String
    public let failures: [String]

    public var passed: Bool { failures.isEmpty }
}

/// Summary of a whole run.
public struct TestReport {
    public let outcomes: [TestOutcome]

    public var total: Int { outcomes.count }
    public var failed: [TestOutcome] { outcomes.filter { !$0.passed } }
    public var passedCount: Int { total - failed.count }
    public var allPassed: Bool { failed.isEmpty }
}
