import Source_Report
import Testing

private let subject = Source.Subject(
    identity: "swift-foundations/swift-example",
    root: "/workspace/swift-example",
    artifacts: [
        .init(path: "Package.swift", kind: .swift, provenance: .authored),
        .init(
            path: ".source/profile.json",
            kind: .configuration,
            provenance: .generated(owner: "continuous-integration-source-policy")
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
    engines: [.init(id: linter, artifactKinds: [.swift])],
    predicates: [.init(id: exactConfiguration, artifactKinds: [.configuration])]
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
        artifactEvidence: [configurationEvidence]
    )

    #expect(try Source.Report.Complete(report, expected: commitment).report.subjects == [subject])
}

@Test
func `complete report rejects an empty expected cohort`() {
    let empty = Source.Report.Commitment(subjects: [], engines: [], predicates: [])
    let report = Source.Report(
        scope: .workspace,
        profile: .init("profile"),
        commitment: empty,
        subjects: [],
        references: [],
        measurements: [],
        artifactEvidence: []
    )

    #expect(throws: Source.Report.Complete.Error.subjects) {
        try Source.Report.Complete(report, expected: empty)
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
        artifactEvidence: []
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
        artifactEvidence: [configurationEvidence]
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
    verdict: .clean
)

private let configurationEvidence = Source.Artifact.Evidence(
    subject: subject.identity,
    artifact: subject.artifacts[1],
    predicate: exactConfiguration,
    verdict: .clean
)
