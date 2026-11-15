import Foundation

/// A minimum of test scaffolding, so the engine can be checked without Xcode.
enum TestKit {
    nonisolated(unsafe) static var current: String = ""
    nonisolated(unsafe) static var failures: [String] = []
    nonisolated(unsafe) static var checks = 0
    nonisolated(unsafe) static var tests = 0

    static func test(_ name: String, _ body: () -> Void) {
        current = name
        tests += 1
        let before = failures.count
        body()
        let mark = failures.count == before ? "\u{2713}" : "\u{2717}"
        print("  \(mark) \(name)")
    }

    static func fail(_ message: String, _ line: Int) {
        failures.append("\(current):\(line) \u{2014} \(message)")
    }

    static func summarise() -> Int32 {
        print("\n\(tests) tests, \(checks) checks, \(failures.count) failures")
        for failure in failures { print("  \u{2717} \(failure)") }
        return failures.isEmpty ? 0 : 1
    }
}

func test(_ name: String, _ body: () -> Void) { TestKit.test(name, body) }

func expect(_ condition: Bool, _ message: @autoclosure () -> String = "expected true",
            line: Int = #line) {
    TestKit.checks += 1
    if !condition { TestKit.fail(message(), line) }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T,
                               _ message: @autoclosure () -> String = "",
                               line: Int = #line) {
    TestKit.checks += 1
    if actual != expected {
        let note = message()
        TestKit.fail("expected \(expected), got \(actual)\(note.isEmpty ? "" : " \u{2014} \(note)")",
                     line)
    }
}

func expectGreater<T: Comparable>(_ a: T, _ b: T,
                                  _ message: @autoclosure () -> String = "",
                                  line: Int = #line) {
    TestKit.checks += 1
    if !(a > b) {
        let note = message()
        TestKit.fail("expected \(a) > \(b)\(note.isEmpty ? "" : " \u{2014} \(note)")", line)
    }
}

func expectLess<T: Comparable>(_ a: T, _ b: T,
                               _ message: @autoclosure () -> String = "",
                               line: Int = #line) {
    TestKit.checks += 1
    if !(a < b) {
        let note = message()
        TestKit.fail("expected \(a) < \(b)\(note.isEmpty ? "" : " \u{2014} \(note)")", line)
    }
}
