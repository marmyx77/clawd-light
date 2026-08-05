import Foundation

/// Collects the failures of a single test case.
///
/// It is the only mutable type in the project, and deliberately so: a test has to
/// be able to record several failures before giving up, otherwise every run shows
/// only the first problem and diagnosis turns into a series of attempts.
public final class Assertions {
    private var collected: [String] = []

    public init() {}

    public var failures: [String] { collected }
    public var passed: Bool { collected.isEmpty }

    // MARK: - Assertions

    public func expect(
        _ condition: Bool,
        _ message: @autoclosure () -> String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard !condition else { return }
        record("\(message())", file: file, line: line)
    }

    public func expectEqual<T: Equatable>(
        _ actual: T,
        _ expected: T,
        _ label: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard actual != expected else { return }
        let prefix = label.isEmpty ? "" : "\(label): "
        record("\(prefix)expected \(expected), got \(actual)", file: file, line: line)
    }

    public func expectNil<T>(
        _ value: T?,
        _ label: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let value else { return }
        let prefix = label.isEmpty ? "" : "\(label): "
        record("\(prefix)expected nil, got \(value)", file: file, line: line)
    }

    public func expectNotNil<T>(
        _ value: T?,
        _ label: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard value == nil else { return }
        let prefix = label.isEmpty ? "" : "\(label): "
        record("\(prefix)expected a value, got nil", file: file, line: line)
    }

    /// Checks that the block throws exactly the expected error.
    public func expectThrows<E: Error & Equatable>(
        _ expected: E,
        _ label: String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () throws -> Void
    ) {
        let prefix = label.isEmpty ? "" : "\(label): "
        do {
            try body()
            record("\(prefix)expected error \(expected), nothing was thrown", file: file, line: line)
        } catch let error as E where error == expected {
            return
        } catch {
            record("\(prefix)expected error \(expected), got \(error)", file: file, line: line)
        }
    }

    public func expectNoThrow(
        _ label: String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () throws -> Void
    ) {
        do {
            try body()
        } catch {
            let prefix = label.isEmpty ? "" : "\(label): "
            record("\(prefix)unexpected error: \(error)", file: file, line: line)
        }
    }

    public func fail(
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        record(message, file: file, line: line)
    }

    // MARK: - Internal

    private func record(_ message: String, file: StaticString, line: UInt) {
        let name = (String(describing: file) as NSString).lastPathComponent
        collected.append("\(name):\(line) — \(message)")
    }
}
