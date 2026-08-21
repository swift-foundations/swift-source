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
            provenance: .generated(
                .init(
                    owner: .init("swift-foundations/swift-example"),
                    input: "continuous-integration-source-policy",
                    revision: "source-enforcement-v3",
                    digest: "configuration-digest"
                )
            )
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
    requirements: [
        .init(
            subject: subject.identity,
            engine: linter,
            artifacts: ["Package.swift"],
            rules: [linterRule]
        )
    ],
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
    #expect(Source.Report.Status(report, expected: commitment) == .clean)
}

@Test
func `report status includes artifact predicate findings`() {
    let evidence = Source.Artifact.Evidence(
        subject: subject.identity,
        artifact: subject.artifacts[1],
        predicate: exactConfiguration,
        verdict: .findings([.init(code: "digest", detail: "configuration differs")])
    )
    let report = Source.Report(
        scope: .workspace,
        profile: .init("profile"),
        commitment: commitment,
        subjects: [subject],
        references: [],
        measurements: [measurement],
        artifactEvidence: [evidence]
    )

    #expect(Source.Report.Status(report, expected: commitment) == .findings)
}

@Test
func `complete report rejects an empty expected cohort`() {
    let empty = Source.Report.Commitment(
        subjects: [],
        engines: [],
        requirements: [],
        predicates: []
    )
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
func `complete report rejects a dropped active rule`() {
    let omitted = Source.Rule.ID(engine: linter, token: "omitted")
    let exact = Source.Report.Commitment(
        subjects: [subject],
        engines: commitment.engines,
        requirements: [
            .init(
                subject: subject.identity,
                engine: linter,
                artifacts: ["Package.swift"],
                rules: [linterRule, omitted]
            )
        ],
        predicates: commitment.predicates
    )
    let report = Source.Report(
        scope: .workspace,
        profile: .init("profile"),
        commitment: exact,
        subjects: [subject],
        references: [],
        measurements: [measurement],
        artifactEvidence: [configurationEvidence]
    )

    #expect(throws: Source.Report.Complete.Error.coverage(subject.identity)) {
        try Source.Report.Complete(report, expected: exact)
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
