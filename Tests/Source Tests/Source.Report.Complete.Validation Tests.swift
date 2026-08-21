import Source_Report
import Testing

@Suite
struct `Source report complete validation` {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
    @Suite struct Integration {}
}

extension `Source report complete validation`.Unit {
    @Test
    func `duplicate findings cannot survive report transport`() {
        let finding = `Source report complete validation`.finding(message: "duplicate")
        let measurement = `Source report complete validation`.measurement(
            findings: [finding, finding],
            repairs: [`Source report complete validation`.repair]
        )

        #expect(
            throws: Source.Report.Complete.Error.coverage(
                `Source report complete validation`.subject.identity
            )
        ) {
            try Source.Report.Complete(
                `Source report complete validation`.report(measurement),
                expected: `Source report complete validation`.commitment
            )
        }
    }
}

extension `Source report complete validation`.`Edge Case` {
    @Test
    func `inapplicable rules cannot carry findings`() {
        let measurement = `Source report complete validation`.measurement(
            applicable: false,
            findings: [`Source report complete validation`.finding(message: "impossible")],
            repairs: [`Source report complete validation`.repair]
        )

        #expect(
            throws: Source.Report.Complete.Error.coverage(
                `Source report complete validation`.subject.identity
            )
        ) {
            try Source.Report.Complete(
                `Source report complete validation`.report(measurement),
                expected: `Source report complete validation`.commitment
            )
        }
    }

    @Test
    func `empty finding reasons cannot survive report transport`() {
        let measurement = `Source report complete validation`.measurement(
            findings: [`Source report complete validation`.finding(message: "")],
            repairs: [`Source report complete validation`.repair]
        )

        #expect(
            throws: Source.Report.Complete.Error.coverage(
                `Source report complete validation`.subject.identity
            )
        ) {
            try Source.Report.Complete(
                `Source report complete validation`.report(measurement),
                expected: `Source report complete validation`.commitment
            )
        }
    }
}

extension `Source report complete validation`.Integration {
    @Test
    func `findings and repair evidence must name the same measured keys`() {
        let measurement = `Source report complete validation`.measurement(
            findings: [`Source report complete validation`.finding(message: "unrepaired")],
            repairs: []
        )

        #expect(
            throws: Source.Report.Complete.Error.coverage(
                `Source report complete validation`.subject.identity
            )
        ) {
            try Source.Report.Complete(
                `Source report complete validation`.report(measurement),
                expected: `Source report complete validation`.commitment
            )
        }
    }
}

extension `Source report complete validation` {
    private static let path = "/workspace/package/Package.swift"
    private static let engine = Source.Engine.ID("swift-linter")
    private static let rule = Source.Rule.ID(engine: engine, token: "rule")
    private static let predicate = Source.Rule.ID(
        engine: .init("source-policy"),
        token: "exact-configuration"
    )
    fileprivate static let subject = Source.Subject(
        identity: "package",
        root: "/workspace/package",
        artifacts: [
            .init(path: "Package.swift", kind: .swift, provenance: .authored, digest: .init("a")),
            .init(path: "profile.json", kind: .configuration, provenance: .authored, digest: .init("b")),
        ]
    )
    fileprivate static let commitment = Source.Report.Commitment(
        subjects: [subject],
        engines: [
            .init(id: engine, artifactKinds: [.swift]),
            .init(id: predicate.engine, artifactKinds: [.configuration]),
        ],
        requirements: [
            .init(
                subject: subject.identity,
                engine: engine,
                artifacts: ["Package.swift"],
                rules: [rule]
            )
        ],
        predicates: [.init(id: predicate, artifactKinds: [.configuration])]
    )
    fileprivate static let repair = Source.Repair.Evidence(
        file: path,
        rule: rule,
        disposition: .unchanged
    )

    fileprivate static func finding(message: Swift.String) -> Source.Finding {
        .init(
            rule: rule,
            diagnostic: .init(
                location: .init(fileID: "Package.swift", filePath: path, line: 1, column: 1),
                severity: .error,
                identifier: rule.token,
                message: message
            ),
            repair: .unavailable(.init(code: "unchanged", detail: "no repair"))
        )
    }

    fileprivate static func measurement(
        applicable: Swift.Bool = true,
        findings: [Source.Finding],
        repairs: [Source.Repair.Evidence]
    ) -> Source.Measurement {
        .init(
            engine: engine,
            subject: subject,
            activeRules: [rule],
            applicableRules: applicable ? [rule] : [],
            files: [path],
            observations: [
                .init(file: path, rule: rule, applicable: applicable, coverage: .measured)
            ],
            repairs: repairs,
            verdict: .findings(findings)
        )
    }

    fileprivate static func report(_ measurement: Source.Measurement) -> Source.Report {
        .init(
            scope: .workspace,
            profile: .init("profile"),
            commitment: commitment,
            subjects: [subject],
            references: [],
            measurements: [measurement],
            artifactEvidence: [
                .init(
                    subject: subject.identity,
                    artifact: subject.artifacts[1],
                    predicate: predicate,
                    actual: .init(digest: .init("b"), schema: .init("1")),
                    expected: .init(digest: .init("b"), schema: .init("1")),
                    verdict: .clean
                )
            ]
        )
    }
}
