import Foundation

var checkCount = 0
var failures: [String] = []

func expect(_ condition: Bool, _ label: String, file: StaticString = #file, line: UInt = #line) {
    checkCount += 1
    if !condition {
        failures.append("FAIL \(label) — expected true (\(file):\(line))")
    }
}

func expectEqual<T: Equatable>(
    _ actual: T, _ expected: T, _ label: String,
    file: StaticString = #file, line: UInt = #line
) {
    checkCount += 1
    if actual != expected {
        failures.append("FAIL \(label) — got \(actual), expected \(expected) (\(file):\(line))")
    }
}

func expectNil<T>(_ value: T?, _ label: String, file: StaticString = #file, line: UInt = #line) {
    checkCount += 1
    if value != nil {
        failures.append("FAIL \(label) — expected nil, got \(value!) (\(file):\(line))")
    }
}

func finish() -> Never {
    if failures.isEmpty {
        print("✅ \(checkCount) checks passed")
        exit(0)
    }
    for failure in failures { print(failure) }
    print("❌ \(failures.count) of \(checkCount) checks failed")
    exit(1)
}
