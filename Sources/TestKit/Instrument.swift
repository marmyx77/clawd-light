import Foundation

/// Proves that the assertions can fail, before anything is measured with them.
///
/// WHY THIS EXISTS
/// The whole credibility of this project rests on one sentence — "497 tests
/// passed" — and that sentence is produced by fifty lines in `Assertions.swift`
/// that nothing ever checked. It was measured: adding a single early `return`
/// at the top of `expect` made the entire suite report success while verifying
/// nothing at all. Not a subtle failure — a full green.
///
/// The same trick was found in a sister project, where three hundred and
/// thirty-six tests passed against a neutralised assertion library. It is not a
/// hypothetical attack; it is what a bad merge, a refactor of the wrong `guard`,
/// or a hurried "let me silence this for a second" looks like afterwards.
///
/// So the instrument is calibrated before it is used. Every assertion is made to
/// fail on purpose and must record it, and made to pass and must stay silent —
/// both directions, because an assertion that always fails is as useless as one
/// that never does.
///
/// HOW IT AVOIDS BEING CIRCULAR
/// Nothing here uses `Assertions` to check `Assertions`. The verdicts are plain
/// Swift comparisons, and a broken instrument ends the process with a code of
/// its own (70, "internal software error") rather than the 1 of an ordinary test
/// failure: the two mean different things, and a reader should not have to guess
/// which one they are looking at.
public enum Instrument {

    /// An error type with nothing to it, for exercising `expectThrows`.
    private enum Sample: Error, Equatable { case one, other }

    /// How many failures a block records. The unit every proof below is stated in.
    private static func failures(_ body: (Assertions) -> Void) -> Int {
        let assertions = Assertions()
        body(assertions)
        return assertions.failures.count
    }

    /// Calibrates the instrument, or ends the process explaining why it cannot.
    public static func prove(quietly: Bool = false) {
        var broken: [String] = []
        var proofs = 0

        func demand(_ held: Bool, _ what: String) {
            proofs += 1
            if !held { broken.append(what) }
        }

        // ── A false claim must be recorded ───────────────────────────────────
        demand(failures { $0.expect(false, "-") } == 1, "expect(false) records nothing")
        demand(failures { $0.expectEqual(1, 2) } == 1, "expectEqual(1, 2) records nothing")
        demand(failures { $0.expectNil(1) } == 1, "expectNil(1) records nothing")
        demand(failures { $0.expectNotNil(Optional<Int>.none) } == 1, "expectNotNil(nil) records nothing")
        demand(failures { $0.fail("-") } == 1, "fail() records nothing")
        demand(
            failures { $0.expectThrows(Sample.one) { } } == 1,
            "expectThrows records nothing when the body throws nothing"
        )
        demand(
            failures { $0.expectThrows(Sample.one) { throw Sample.other } } == 1,
            "expectThrows records nothing when the wrong error arrives"
        )
        demand(
            failures { $0.expectNoThrow { throw Sample.one } } == 1,
            "expectNoThrow records nothing when the body throws"
        )

        // ── A true claim must stay silent ────────────────────────────────────
        // An assertion that fires on everything is noise, and noise is ignored,
        // which lands in the same place as an assertion that never fires.
        demand(failures { $0.expect(true, "-") } == 0, "expect(true) records a failure")
        demand(failures { $0.expectEqual(1, 1) } == 0, "expectEqual(1, 1) records a failure")
        demand(failures { $0.expectNil(Optional<Int>.none) } == 0, "expectNil(nil) records a failure")
        demand(failures { $0.expectNotNil(1) } == 0, "expectNotNil(1) records a failure")
        demand(
            failures { $0.expectThrows(Sample.one) { throw Sample.one } } == 0,
            "expectThrows records a failure when the expected error arrives"
        )
        demand(failures { $0.expectNoThrow { } } == 0, "expectNoThrow records a failure on a quiet body")

        // ── Several failures in one case must all survive ────────────────────
        // The collector is the only mutable type in the project; if it kept just
        // the last one, diagnosis would silently become a guessing game.
        demand(
            failures { $0.expect(false, "a"); $0.expect(false, "b"); $0.expect(false, "c") } == 3,
            "three failures in one case do not all reach the report"
        )

        // ── And the failure must reach the exit code ─────────────────────────
        // Recording a failure nobody acts on is the same as not recording it: CI
        // reads the exit code and nothing else.
        let red = TestSuite("instrument", [TestCase("must fail", { $0.fail("deliberate") })])
        let report = TestRunner.run([red])
        demand(report.allPassed == false, "a suite with a failing case reports that everything passed")
        demand(report.failed.count == 1, "the failing case is missing from the report")
        demand(
            TestRunner.runAndReport([red], printing: { _ in }) != 0,
            "a failing run still exits zero"
        )

        let green = TestSuite("instrument", [TestCase("must pass", { $0.expect(true, "-") })])
        demand(
            TestRunner.runAndReport([green], printing: { _ in }) == 0,
            "a passing run does not exit zero"
        )

        guard broken.isEmpty else {
            var message = """

                ✗ THE INSTRUMENT IS BLUNT — nothing below this line can be trusted.

                  \(broken.count) of \(proofs) proofs failed. The assertions used by every
                  test in this project do not behave as they claim to, so a run that
                  reports success would be reporting the absence of measurement:

                """
            for problem in broken { message += "\n    · \(problem)" }
            message += """


                  Look at Sources/TestKit/Assertions.swift before looking anywhere else.

                """
            FileHandle.standardError.write(Data(message.utf8))
            exit(70)
        }

        if !quietly {
            print("▸ Instrument proved: \(proofs) checks, the assertions bite.")
        }
    }
}
