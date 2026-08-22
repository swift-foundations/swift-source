import Source_Report
import Testing

private let subject = Source.Subject(
  identity: "swift-foundations/swift-example",
  root: "/workspace/swift-example",
  artifacts: [
    .init(
      path: "Package.swift",
      kind: .swift,
      purpose: .governedSource,
      provenance: .authored,
      digest: .init("package")
    ),
    .init(
      path: ".source/profile.json",
      kind: .configuration,
      purpose: .generatedPolicy,
      provenance: .generated(
        .init(
          owner: .init("swift-foundations/swift-example"),
          input: "continuous-integration-source-policy",
          revision: "source-enforcement-v3",
          digest: "configuration-digest"
        )
      ),
      digest: .init("configuration")
    ),
    .init(
      path: "Controls/nest-name.json",
      kind: .configuration,
      purpose: .control(
        .init(
          identity: "nest-name-positive",
          predicate: linterRule,
          expectation: .findings(1)
        )
      ),
      provenance: .authored,
      digest: .init("nest-name-control")
    ),
    .init(
      path: "Controls/configuration.json",
      kind: .configuration,
      purpose: .control(
        .init(
          identity: "configuration-positive",
          predicate: exactConfiguration,
          expectation: .findings(1)
        )
      ),
      provenance: .authored,
      digest: .init("configuration-control")
    ),
  ]
)
private let linter = Source.Engine.ID("swift-linter")
private let linterRule = Source.Rule.ID(engine: linter, token: "nest.name")
private let exactConfiguration = Source.Rule.ID(
  engine: .init("source-policy"),
  token: "exact-configuration"
)
private let commitment = Source.Report.Commitment(
  subjects: [subject],
  engines: [
    .init(id: linter, artifactKinds: [.swift]),
    .init(id: exactConfiguration.engine, artifactKinds: [.configuration]),
  ],
  rules: [
    .init(id: linterRule, controls: ["nest-name-positive"]),
    .init(id: exactConfiguration, controls: ["configuration-positive"]),
  ],
  requirements: [
    .init(
      subject: subject.identity,
      engine: linter,
      artifacts: ["Package.swift"],
      rules: [linterRule]
    )
  ],
  predicates: [.init(id: exactConfiguration, artifactKinds: [.configuration])],
  predicateRequirements: [
    .init(
      subject: subject.identity,
      artifacts: [".source/profile.json"],
      predicates: [exactConfiguration]
    )
  ]
)

@Test
func `complete report proves exact subjects engines and artifact predicates`() throws {
  let report = Source.Report(
    scope: .workspace,
    profile: .init("profile"),
    commitment: commitment,
    subjects: [subject],
    references: [],
    measurements: [measurement],
    artifactEvidence: [configurationEvidence],
    controlEvidence: controlEvidence
  )

  #expect(try Source.Report.Complete(report, expected: commitment).report.subjects == [subject])
  #expect(Source.Report.Status(report, expected: commitment) == .clean)
}

@Test
func `report status includes artifact predicate findings`() {
  let evidence = Source.Artifact.Evidence(
    subject: subject.identity,
    artifact: subject.artifacts[1],
    predicate: exactConfiguration,
    actual: .init(digest: .init("different"), schema: .init("1")),
    expected: .init(digest: .init("configuration"), schema: .init("1")),
    verdict: .findings([.init(code: "digest", detail: "configuration differs")])
  )
  let report = Source.Report(
    scope: .workspace,
    profile: .init("profile"),
    commitment: commitment,
    subjects: [subject],
    references: [],
    measurements: [measurement],
    artifactEvidence: [evidence],
    controlEvidence: controlEvidence
  )

  #expect(Source.Report.Status(report, expected: commitment) == .findings)
}

@Test
func `report status includes measured control failures`() {
  let failedControls = [
    controlEvidence[0],
    Source.Rule.Control.Evidence(
      identity: "configuration-positive",
      rule: exactConfiguration,
      expectation: .findings(1),
      actualFindings: 0,
      verdict: .findings([.init(code: "control-count", detail: "expected 1, received 0")])
    ),
  ]
  let report = Source.Report(
    scope: .workspace,
    profile: .init("profile"),
    commitment: commitment,
    subjects: [subject],
    references: [],
    measurements: [measurement],
    artifactEvidence: [configurationEvidence],
    controlEvidence: failedControls
  )

  #expect((try? Source.Report.Complete(report, expected: commitment)) != nil)
  #expect(Source.Report.Status(report, expected: commitment) == .findings)
}

@Test
func `complete report rejects an empty expected cohort`() {
  let empty = Source.Report.Commitment(
    subjects: [],
    engines: [],
    rules: [],
    requirements: [],
    predicates: [],
    predicateRequirements: []
  )
  let report = Source.Report(
    scope: .workspace,
    profile: .init("profile"),
    commitment: empty,
    subjects: [],
    references: [],
    measurements: [],
    artifactEvidence: [],
    controlEvidence: []
  )

  #expect(throws: Source.Report.Complete.Error.subjects) {
    try Source.Report.Complete(report, expected: empty)
  }
}

@Test
func `complete report rejects a dropped active rule`() {
  let dropped = Source.Measurement(
    engine: linter,
    subject: subject,
    activeRules: [],
    applicableRules: [],
    files: ["/workspace/swift-example/Package.swift"],
    observations: [],
    controls: [controlEvidence[0]],
    verdict: .clean
  )
  let report = Source.Report(
    scope: .workspace,
    profile: .init("profile"),
    commitment: commitment,
    subjects: [subject],
    references: [],
    measurements: [dropped],
    artifactEvidence: [configurationEvidence],
    controlEvidence: controlEvidence
  )

  #expect(throws: Source.Report.Complete.Error.coverage(subject.identity)) {
    try Source.Report.Complete(report, expected: commitment)
  }
}

@Test
func `complete report rejects omitted generated configuration evidence`() {
  let report = Source.Report(
    scope: .workspace,
    profile: .init("profile"),
    commitment: commitment,
    subjects: [subject],
    references: [],
    measurements: [measurement],
    artifactEvidence: [],
    controlEvidence: controlEvidence
  )

  #expect(throws: Source.Report.Complete.Error.artifacts(subject.identity)) {
    try Source.Report.Complete(report, expected: commitment)
  }
}

@Test
func `complete report rejects an extra engine measurement`() {
  let report = Source.Report(
    scope: .workspace,
    profile: .init("profile"),
    commitment: commitment,
    subjects: [subject],
    references: [],
    measurements: [measurement, measurement],
    artifactEvidence: [configurationEvidence],
    controlEvidence: controlEvidence
  )

  #expect(throws: Source.Report.Complete.Error.engines(subject.identity)) {
    try Source.Report.Complete(report, expected: commitment)
  }
}

private let measurement = Source.Measurement(
  engine: linter,
  subject: subject,
  activeRules: [linterRule],
  applicableRules: [linterRule],
  files: ["/workspace/swift-example/Package.swift"],
  observations: [
    .init(
      file: "/workspace/swift-example/Package.swift",
      rule: linterRule,
      applicable: true,
      coverage: .measured
    )
  ],
  controls: [controlEvidence[0]],
  verdict: .clean
)

private let configurationEvidence = Source.Artifact.Evidence(
  subject: subject.identity,
  artifact: subject.artifacts[1],
  predicate: exactConfiguration,
  actual: .init(digest: .init("configuration"), schema: .init("1")),
  expected: .init(digest: .init("configuration"), schema: .init("1")),
  verdict: .clean
)

private let controlEvidence: [Source.Rule.Control.Evidence] = [
  .init(
    identity: "nest-name-positive",
    rule: linterRule,
    expectation: .findings(1),
    actualFindings: 1,
    verdict: .clean
  ),
  .init(
    identity: "configuration-positive",
    rule: exactConfiguration,
    expectation: .findings(1),
    actualFindings: 1,
    verdict: .clean
  ),
]
