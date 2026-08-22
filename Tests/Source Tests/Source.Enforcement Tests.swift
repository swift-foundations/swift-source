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
    artifactKinds: [.swift],
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
        artifactKinds: [.swift],
        rules: [rule]
      )
    ]
  )
  let execution = try Source.Execution(drivers: [])
  let result = await execution.measure(
    .init(
      identity: "package",
      root: "/package",
      artifacts: [
        .init(
          path: "A.swift",
          kind: .swift,
          purpose: .governedSource,
          provenance: .authored,
          digest: .init("a")
        )
      ]
    ),
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
    commitment: .init(
      subjects: [],
      engines: [],
      rules: [],
      requirements: [],
      predicates: [],
      predicateRequirements: []
    ),
    subjects: [],
    references: [],
    measurements: [],
    artifactEvidence: [],
    controlEvidence: []
  )
  #expect(throws: Source.Report.Complete.Error.partial) {
    try Source.Report.Complete(
      report,
      expected: .init(
        subjects: [],
        engines: [],
        rules: [],
        requirements: [],
        predicates: [],
        predicateRequirements: []
      )
    )
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
    read: { path in
      state.withLock { $0.files[path].map(Result.success) ?? .failure(unavailable) }
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
  switch Source.Repair.Transaction().apply([
    .init(
      plan: plan,
      subject: plan.subject,
      profile: plan.profile,
      sources: plan.sources,
      files: files
    )
  ]) {
  case .success:
    Issue.record("Expected the second write to fail")
  case .failure(let reason):
    #expect(reason == failure)
  }
  #expect(state.withLock { $0.files } == ["A": [1], "B": [2]])
}

@Test
func `repair rolls back an earlier subject when a later subject fails`() {
  let first = Mutex(["A": [UInt8](arrayLiteral: 1)])
  let second = Mutex(["B": [UInt8](arrayLiteral: 2)])
  let missing = Source.Reason(code: "missing", detail: "missing")
  let injected = Source.Reason(code: "injected", detail: "second subject")
  let firstFiles = Source.Repair.FileSystem(
    exists: { path in first.withLock { $0[path] != nil } },
    read: { path in first.withLock { $0[path].map(Result.success) ?? .failure(missing) } },
    write: { path, contents in
      first.withLock { $0[path] = contents }
      return .success(())
    },
    move: { _, _ in .failure(missing) },
    delete: { _ in .failure(missing) }
  )
  let secondFiles = Source.Repair.FileSystem(
    exists: { path in second.withLock { $0[path] != nil } },
    read: { path in second.withLock { $0[path].map(Result.success) ?? .failure(missing) } },
    write: { _, _ in .failure(injected) },
    move: { _, _ in .failure(missing) },
    delete: { _ in .failure(missing) }
  )
  let digest: ([UInt8]) -> Swift.String = {
    FIPS_180_4.SHA256.digest($0.map(Byte.init)).hex
  }
  func plan(
    _ identity: Swift.String,
    path: Swift.String,
    original: UInt8,
    replacement: UInt8
  )
    -> Source.Repair.Plan
  {
    .init(
      subject: .init(identity: identity, digest: identity),
      profile: .init("profile"),
      sources: .init("sources-\(identity)"),
      operations: [
        .rewrite(path: path, expected: digest([original]), replacement: [replacement])
      ],
      refusals: [],
      postconditions: [.file(path: path, digest: digest([replacement]))]
    )
  }
  let firstPlan = plan("first", path: "A", original: 1, replacement: 3)
  let secondPlan = plan("second", path: "B", original: 2, replacement: 4)

  let result = Source.Repair.Transaction().apply([
    .init(
      plan: firstPlan,
      subject: firstPlan.subject,
      profile: firstPlan.profile,
      sources: firstPlan.sources,
      files: firstFiles
    ),
    .init(
      plan: secondPlan,
      subject: secondPlan.subject,
      profile: secondPlan.profile,
      sources: secondPlan.sources,
      files: secondFiles
    ),
  ])

  guard case .failure(let reason) = result else {
    Issue.record("expected the later subject to fail")
    return
  }
  #expect(reason == injected)
  #expect(first.withLock { $0["A"] } == [1])
  #expect(second.withLock { $0["B"] } == [2])
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
  let subject = Source.Subject(
    identity: "package",
    root: "/package",
    artifacts: [
      .init(
        path: "A.swift",
        kind: .swift,
        purpose: .governedSource,
        provenance: .authored,
        digest: .init("a")
      )
    ]
  )
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
            path: "/package/A.swift",
            contents: Swift.String(decoding: replacement, as: UTF8.self)
          )
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
    rules: nil,
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
  switch Source.Repair.Transaction().apply([
    .init(
      plan: plan,
      subject: subject.binding,
      profile: profile,
      sources: sources,
      files: files
    )
  ]) {
  case .success: break
  case .failure(let reason): Issue.record("unexpected failure: \(reason.code)")
  }
  #expect(state.withLock { $0["A.swift"] } == replacement)
}

@Test
func `rule scoped repair still accepts clean remeasurement by every engine`() throws {
  let original = [UInt8]("let x = 1\n".utf8)
  let replacement = [UInt8]("let value = 1\n".utf8)
  let unavailable = Source.Reason(code: "missing", detail: "missing")
  let files = Source.Repair.FileSystem(
    exists: { $0 == "A.swift" },
    read: { path in path == "A.swift" ? .success(original) : .failure(unavailable) },
    write: { _, _ in .failure(unavailable) },
    move: { _, _ in .failure(unavailable) },
    delete: { _ in .failure(unavailable) }
  )
  let subject = Source.Subject(
    identity: "package",
    root: "/package",
    artifacts: [
      .init(
        path: "A.swift",
        kind: .swift,
        purpose: .governedSource,
        provenance: .authored,
        digest: .init("a")
      )
    ]
  )
  let linter = Source.Engine.ID("swift-linter")
  let format = Source.Engine.ID("swift-format")
  let selected = Source.Rule.ID(engine: linter, token: "selected")
  let formatting = Source.Rule.ID(engine: format, token: "formatting")
  let finding = Source.Finding(
    rule: selected,
    diagnostic: .init(
      location: .init(fileID: "A.swift", filePath: "/package/A.swift", line: 1, column: 5),
      severity: .error,
      identifier: "selected",
      message: "rename"
    ),
    repair: .automatic
  )
  let measured = [
    Source.Measurement(
      engine: linter,
      subject: subject,
      activeRules: [selected],
      applicableRules: [selected],
      files: ["/package/A.swift"],
      observations: [
        .init(
          file: "/package/A.swift",
          rule: selected,
          applicable: true,
          coverage: .measured
        )
      ],
      repairs: [
        .init(
          file: "/package/A.swift",
          rule: selected,
          disposition: .edits([
            .rewrite(
              path: "/package/A.swift",
              contents: Swift.String(decoding: replacement, as: UTF8.self)
            )
          ])
        )
      ],
      verdict: .findings([finding])
    ),
    Source.Measurement(
      engine: format,
      subject: subject,
      activeRules: [formatting],
      applicableRules: [formatting],
      files: ["/package/A.swift"],
      observations: [
        .init(
          file: "/package/A.swift",
          rule: formatting,
          applicable: true,
          coverage: .measured
        )
      ],
      verdict: .clean
    ),
  ]
  let staging = try Source.Repair.Staging(
    subject: subject,
    profile: .init("profile"),
    sources: Source.SourceSet.digest([.init(path: "A.swift", contents: original)]),
    measurements: measured,
    rules: [selected],
    fileSystem: files
  )
  let remeasured = measured.map { measurement in
    Source.Measurement(
      engine: measurement.engine,
      subject: subject,
      activeRules: measurement.activeRules,
      applicableRules: measurement.applicableRules,
      files: measurement.files,
      observations: measurement.observations,
      verdict: .clean
    )
  }

  #expect(staging.finish(remeasured: remeasured).refusals.isEmpty)
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
  let result = Source.Repair.Transaction().apply([
    .init(
      plan: plan,
      subject: .init(identity: "package", digest: "other"),
      profile: plan.profile,
      sources: plan.sources,
      files: files
    )
  ])
  guard case .failure(let failure) = result else {
    Issue.record("expected stale binding refusal")
    return
  }
  #expect(failure.code == "stale-subject")
  #expect(state.withLock { $0["A"] } == [1])
}
