import Source_Execution
import Source_Repair
import Source_Report
import Source_Test_Support
import Synchronization
import Testing

@Test
func `profile identity is content addressed and deterministic`() {
  let engine = Source.Profile.Engine(
    id: .init("swift-linter"),
    executable: "/tool",
        tool: .init("tool"),
        configuration: .init("configuration"),
        configurationPath: "/configuration",
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
                configurationPath: "/configuration",
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
    read: { path in state.withLock { $0.files[path].map(Result.success) ?? .failure(unavailable) }
    },
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
  switch Source.Repair.Transaction(files: files).apply(
    plan,
    subject: plan.subject,
    profile: plan.profile,
    sources: plan.sources
  ) {
  case .success:
    Issue.record("Expected the second write to fail")
  case .failure(let reason):
    #expect(reason == failure)
  }
  #expect(state.withLock { $0.files } == ["A": [1], "B": [2]])
}

@Test
func `repair stages remeasures and publishes bound bytes`() throws {
  let original = [UInt8]("let x = 1\n".utf8)
  let replacement = [UInt8]("let value = 1\n".utf8)
  let state = Mutex(["A.swift": original])
  let unavailable = Source.Reason(code: "missing", detail: "missing")
  let files = Source.Repair.FileSystem(
    exists: { path in state.withLock { $0[path] != nil } },
    read: { path in state.withLock { $0[path].map(Result.success) ?? .failure(unavailable) } },
    write: { path, contents in
      state.withLock { $0[path] = contents }
      return .success(())
    },
    move: { from, to in
      state.withLock {
        guard let contents = $0.removeValue(forKey: from) else {
          return .failure(unavailable)
        }
        $0[to] = contents
        return .success(())
      }
    },
    delete: { path in
      state.withLock {
        guard $0.removeValue(forKey: path) != nil else { return .failure(unavailable) }
        return .success(())
      }
    }
  )
  let subject = Source.Subject(identity: "package", root: "/package", files: ["A.swift"])
  let engine = Source.Engine.ID("swift-linter")
  let rule = Source.Rule.ID(engine: engine, token: "rule")
  let finding = Source.Finding(
    rule: rule,
    diagnostic: .init(
      location: .init(fileID: "A.swift", filePath: "/package/A.swift", line: 1, column: 5),
      severity: .error,
      identifier: "rule",
      message: "rename"
    ),
    repair: .automatic
  )
  let measured = Source.Measurement(
    engine: engine,
    subject: subject,
    activeRules: [rule],
    applicableRules: [rule],
    files: ["/package/A.swift"],
    observations: [
      .init(file: "/package/A.swift", rule: rule, applicable: true, coverage: .measured)
    ],
    repairs: [
      .init(
        file: "/package/A.swift",
        rule: rule,
        disposition: .edits([
          .rewrite(
            path: "/package/A.swift", contents: Swift.String(decoding: replacement, as: UTF8.self))
        ])
      )
    ],
    verdict: .findings([finding])
  )
  let sources = Source.SourceSet.digest([
    .init(path: "A.swift", contents: original)
  ])
  let profile = Source.Profile.Digest("profile")
  let staging = try Source.Repair.Staging(
    subject: subject,
    profile: profile,
    sources: sources,
    measurements: [measured],
    fileSystem: files
  )
  #expect(state.withLock { $0["A.swift"] } == original)
  #expect(staging.files == [.init(path: "A.swift", contents: replacement)])

  let clean = Source.Measurement(
    engine: engine,
    subject: subject,
    activeRules: [rule],
    applicableRules: [rule],
    files: ["/package/A.swift"],
    observations: [
      .init(file: "/package/A.swift", rule: rule, applicable: true, coverage: .measured)
    ],
    verdict: .clean
  )
  let plan = staging.finish(remeasured: [clean])
  #expect(plan.refusals.isEmpty)
  switch Source.Repair.Transaction(files: files).apply(
    plan,
    subject: subject.binding,
    profile: profile,
    sources: sources
  ) {
  case .success: break
  case .failure(let reason): Issue.record("unexpected failure: \(reason.code)")
  }
  #expect(state.withLock { $0["A.swift"] } == replacement)
}

@Test
func `repair refuses stale plan bindings before publication`() {
  let state = Mutex(["A": [UInt8](arrayLiteral: 1)])
  let reason = Source.Reason(code: "missing", detail: "missing")
  let files = Source.Repair.FileSystem(
    exists: { path in state.withLock { $0[path] != nil } },
    read: { path in state.withLock { $0[path].map(Result.success) ?? .failure(reason) } },
    write: { path, contents in
      state.withLock { $0[path] = contents }
      return .success(())
    },
    move: { _, _ in .failure(reason) },
    delete: { _ in .failure(reason) }
  )
  let plan = Source.Repair.Plan(
    subject: .init(identity: "package", digest: "subject"),
    profile: .init("profile"),
    sources: .init("sources"),
    operations: [.rewrite(path: "A", expected: "wrong", replacement: [2])],
    refusals: [],
    postconditions: []
  )
  let result = Source.Repair.Transaction(files: files).apply(
    plan,
    subject: .init(identity: "package", digest: "other"),
    profile: plan.profile,
    sources: plan.sources
  )
  guard case .failure(let failure) = result else {
    Issue.record("expected stale binding refusal")
    return
  }
  #expect(failure.code == "stale-subject")
  #expect(state.withLock { $0["A"] } == [1])
}
