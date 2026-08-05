import Foundation

/// Runs the suites and prints a report readable from a terminal.
///
/// It exists because the macOS Command Line Tools toolchain, without Xcode,
/// provides neither XCTest nor the complete swift-testing. The trade-off is
/// acceptable: what's needed here is running pure assertions, not profiling or
/// parallelizing.
public enum TestRunner {

    /// Runs every suite and returns the report. It prints nothing: separating
    /// execution from presentation keeps the runner itself testable.
    public static func run(_ suites: [TestSuite]) -> TestReport {
        let outcomes = suites.flatMap { suite in
            suite.cases.map { testCase -> TestOutcome in
                let assertions = Assertions()
                testCase.body(assertions)
                return TestOutcome(
                    suite: suite.name,
                    name: testCase.name,
                    failures: assertions.failures
                )
            }
        }
        return TestReport(outcomes: outcomes)
    }

    /// Runs the suites, prints the report and returns the exit code.
    @discardableResult
    public static func runAndReport(_ suites: [TestSuite], filter: String? = nil) -> Int32 {
        let selected = filter.map { needle in
            suites.compactMap { suite -> TestSuite? in
                if suite.name.localizedCaseInsensitiveContains(needle) { return suite }
                let matching = suite.cases.filter {
                    $0.name.localizedCaseInsensitiveContains(needle)
                }
                return matching.isEmpty ? nil : TestSuite(suite.name, matching)
            }
        } ?? suites

        let report = run(selected)
        print(format(report))
        return report.allPassed ? 0 : 1
    }

    /// Formats the report. Pure: no I/O, so it can be verified.
    public static func format(_ report: TestReport) -> String {
        var lines: [String] = []
        var currentSuite: String?

        for outcome in report.outcomes {
            if outcome.suite != currentSuite {
                lines.append("")
                lines.append("\(outcome.suite)")
                currentSuite = outcome.suite
            }
            let mark = outcome.passed ? "  ✓" : "  ✗"
            lines.append("\(mark) \(outcome.name)")
            for failure in outcome.failures {
                lines.append("      \(failure)")
            }
        }

        lines.append("")
        lines.append(String(repeating: "─", count: 56))
        if report.allPassed {
            lines.append("\(report.total) tests passed.")
        } else {
            lines.append("\(report.passedCount)/\(report.total) passed — \(report.failed.count) failed:")
            for outcome in report.failed {
                lines.append("  · \(outcome.suite) › \(outcome.name)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
