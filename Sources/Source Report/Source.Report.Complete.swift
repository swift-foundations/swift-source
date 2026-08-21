extension Source.Report {
    public struct Complete: Sendable {
        public let report: Source.Report

        public init(
            _ report: Source.Report,
            expected commitment: Source.Report.Commitment
        ) throws(Error) {
            guard report.scope == .workspace else { throw .partial }
            guard report.references.isEmpty else { throw .references }
            guard report.commitment == commitment else { throw .commitment }
            guard !commitment.subjects.isEmpty else { throw .subjects }
            let identities = commitment.subjects.map(\.identity)
            guard Set(identities).count == identities.count,
                report.subjects == commitment.subjects
            else { throw .subjects }
            let engineIDs = commitment.engines.map(\.id)
            guard Set(engineIDs).count == engineIDs.count else { throw .commitment }
            let predicateIDs = commitment.predicates.map(\.id)
            guard Set(predicateIDs).count == predicateIDs.count else { throw .commitment }

            var expectedMeasurements = 0
            for subject in commitment.subjects {
                let paths = subject.artifacts.map(\.path)
                guard !paths.isEmpty, Set(paths).count == paths.count else {
                    throw .artifacts(subject.identity)
                }
                let measurements = report.measurements.filter { $0.subject.identity == subject.identity }
                for requirement in commitment.engines {
                    let artifacts = subject.artifacts.filter {
                        requirement.artifactKinds.contains($0.kind)
                    }
                    guard !artifacts.isEmpty else { continue }
                    expectedMeasurements += 1
                    let matching = measurements.filter { $0.engine == requirement.id }
                    guard matching.count == 1, let measurement = matching.first else {
                        throw .engines(subject.identity)
                    }
                    guard measurement.subject == subject,
                        measurement.files
                            == Self.absolute(
                                artifacts.map(\.path),
                                under: subject.root
                            ),
                        !measurement.activeRules.isEmpty,
                        !measurement.applicableRules.isEmpty
                    else { throw .coverage(subject.identity) }
                    switch measurement.verdict {
                    case .clean, .findings: break
                    case .unmeasured, .notRequested: throw .coverage(subject.identity)
                    }
                }
                let requiredEngines = Set(
                    commitment.engines.compactMap { requirement in
                        subject.artifacts.contains { requirement.artifactKinds.contains($0.kind) }
                            ? requirement.id : nil
                    }
                )
                guard Set(measurements.map(\.engine)) == requiredEngines else {
                    throw .engines(subject.identity)
                }

                for artifact in subject.artifacts {
                    let engineCoverage = commitment.engines.contains {
                        $0.artifactKinds.contains(artifact.kind)
                    }
                    let predicates = commitment.predicates.filter {
                        $0.artifactKinds.contains(artifact.kind)
                    }
                    guard engineCoverage || !predicates.isEmpty else {
                        throw .artifacts(subject.identity)
                    }
                    for predicate in predicates {
                        let evidence = report.artifactEvidence.filter {
                            $0.subject == subject.identity
                                && $0.artifact == artifact
                                && $0.predicate == predicate.id
                        }
                        guard evidence.count == 1, let measured = evidence.first else {
                            throw .artifacts(subject.identity)
                        }
                        if case .unmeasured = measured.verdict {
                            throw .artifacts(subject.identity)
                        }
                    }
                }
            }
            guard report.measurements.count == expectedMeasurements else {
                throw .engines("unexpected measurement")
            }
            let expectedEvidence = commitment.subjects.flatMap { subject in
                subject.artifacts.flatMap { artifact in
                    commitment.predicates.filter { $0.artifactKinds.contains(artifact.kind) }
                        .map { (subject.identity, artifact, $0.id) }
                }
            }
            guard report.artifactEvidence.count == expectedEvidence.count else {
                throw .artifacts("unexpected evidence")
            }
            self.report = report
        }

        private static func absolute(
            _ paths: [Swift.String],
            under root: Swift.String
        ) -> [Swift.String] {
            paths.map { path in
                if path.hasPrefix("/") { return path }
                return root.hasSuffix("/") ? root + path : root + "/" + path
            }.sorted()
        }
    }
}
