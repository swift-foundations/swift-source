import Synchronization
import Testing
import Source_Execution
import Source_Repair
import Source_Report
import Source_Test_Support

@Test
func `profile identity is content addressed and deterministic`() {
    let engine = Source.Profile.Engine(
        id: .init("swift-linter"),
        executable: "/tool",
        tool: .init("tool"),
        configuration: .init("configuration"),
        rules: [.init(engine: .init("swift-linter"), token: "rule")]
    )
    let left = Source.Profile(revision: "1", engines: [engine])
    let right = Source.Profile(revision: "1", engines: [engine])
    #expect(left.digest == right.digest)
    #expect(left.digest.hex.count == 64)
}

@Test
func `execution fails closed when an engine driver is absent`() async throws {
    let rule = Source.Rule.ID(engine: .init("swift-linter"), token: "rule")
    let profile = Source.Profile(
        revision: "1",
        engines: [
            .init(
                id: .init("swift-linter"),
                executable: "/tool",
                tool: .init("tool"),
                configuration: .init("configuration"),
                rules: [rule]
            )
        ]
    )
    let execution = try Source.Execution(drivers: [])
    let result = await execution.measure(
        .init(identity: "package", root: "/package", files: ["A.swift"]),
        profile: profile
    )
    guard case .unmeasured(let reasons) = result[0].verdict else {
        Issue.record("expected UNMEASURED")
        return
    }
    #expect(reasons.map(\.code) == ["missing-driver"])
}

@Test
func `complete report rejects partial evidence`() {
    let report = Source.Report(
        scope: .partial,
        profile: .init("profile"),
        subjects: [],
        references: [],
        measurements: []
    )
    #expect(throws: Source.Report.Complete.Error.partial) {
        try Source.Report.Complete(report, required: [])
    }
}

@Test
func `repair rolls back every published operation after a later failure`() {
    struct State: Sendable {
        var files: [Swift.String: [UInt8]]
        var writes: Swift.Int
    }
    let state = Mutex(State(files: ["A": [1], "B": [2]], writes: 0))
    let unavailable = Source.Reason(code: "missing", detail: "missing")
    let failure = Source.Reason(code: "injected", detail: "second write")
    let files = Source.Repair.FileSystem(
        exists: { path in state.withLock { $0.files[path] != nil } },
        read: { path in state.withLock { $0.files[path].map(Result.success) ?? .failure(unavailable) } },
        write: { path, contents in
            state.withLock {
                $0.writes += 1
                if $0.writes == 2 { return .failure(failure) }
                $0.files[path] = contents
                return .success(())
            }
        },
        move: { from, to in
            state.withLock {
                guard let contents = $0.files.removeValue(forKey: from) else {
                    return .failure(unavailable)
                }
                $0.files[to] = contents
                return .success(())
            }
        },
        delete: { path in
            state.withLock {
                guard $0.files.removeValue(forKey: path) != nil else {
                    return .failure(unavailable)
                }
                return .success(())
            }
        }
    )
    let digest: ([UInt8]) -> Swift.String = {
        FIPS_180_4.SHA256.digest($0.map(Byte.init)).hex
    }
    let plan = Source.Repair.Plan(
        subject: .init(identity: "package", digest: "subject"),
        profile: .init("profile"),
        sources: .init("sources"),
        operations: [
            .rewrite(path: "A", expected: digest([1]), replacement: [3]),
            .rewrite(path: "B", expected: digest([2]), replacement: [4]),
        ],
        refusals: [],
        postconditions: []
    )
    switch Source.Repair.Transaction(files: files).apply(plan) {
    case .success:
        Issue.record("Expected the second write to fail")
    case .failure(let reason):
        #expect(reason == failure)
    }
    #expect(state.withLock { $0.files } == ["A": [1], "B": [2]])
}
