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
            guard Set(engineIDs).count == engineIDs.count,
                commitment.engines.allSatisfy({
                    !$0.artifactKinds.isEmpty
                        && Set($0.artifactKinds).count == $0.artifactKinds.count
                })
            else { throw .commitment }
            let predicateIDs = commitment.predicates.map(\.id)
            guard Set(predicateIDs).count == predicateIDs.count,
                commitment.predicates.allSatisfy({
                    !$0.artifactKinds.isEmpty
                        && Set($0.artifactKinds).count == $0.artifactKinds.count
                        && engineIDs.contains($0.id.engine)
                })
            else { throw .commitment }
            let subjectIDs = Set(identities)
            let requirementKeys = commitment.requirements.map {
                "\($0.subject)\u{0}\($0.engine.token)"
            }
            guard Set(requirementKeys).count == requirementKeys.count else { throw .commitment }
            for requirement in commitment.requirements {
                guard subjectIDs.contains(requirement.subject),
                    engineIDs.contains(requirement.engine),
                    !requirement.artifacts.isEmpty,
                    Set(requirement.artifacts).count == requirement.artifacts.count,
                    !requirement.rules.isEmpty,
                    Set(requirement.rules).count == requirement.rules.count,
                    requirement.rules.allSatisfy({ $0.engine == requirement.engine }),
                    let subject = commitment.subjects.first(where: {
                        $0.identity == requirement.subject
                    }),
                    let engine = commitment.engines.first(where: { $0.id == requirement.engine }),
                    requirement.artifacts.allSatisfy({ path in
                        subject.artifacts.contains {
                            $0.path == path && engine.artifactKinds.contains($0.kind)
                        }
                    })
                else { throw .commitment }
            }
            let usedEngines = Set(commitment.requirements.map(\.engine))
                .union(commitment.predicates.map(\.id.engine))
            guard usedEngines == Set(engineIDs),
                commitment.predicates.allSatisfy({ predicate in
                    commitment.subjects.contains { subject in
                        subject.artifacts.contains { predicate.artifactKinds.contains($0.kind) }
                    }
                })
            else { throw .commitment }

            for subject in commitment.subjects {
                let paths = subject.artifacts.map(\.path)
                guard !paths.isEmpty, Set(paths).count == paths.count else {
                    throw .artifacts(subject.identity)
                }
                let measurements = report.measurements.filter {
                    $0.subject.identity == subject.identity
                }
                let requirements = commitment.requirements.filter {
                    $0.subject == subject.identity
                }
                for requirement in requirements {
                    let artifacts = subject.artifacts.filter {
                        requirement.artifacts.contains($0.path)
                    }
                    let matching = measurements.filter { $0.engine == requirement.engine }
                    guard matching.count == 1, let measurement = matching.first else {
                        throw .engines(subject.identity)
                    }
                    guard measurement.subject == subject,
                        measurement.files
                            == Self.absolute(
                                artifacts.map(\.path),
                                under: subject.root
                            ),
                        Set(measurement.activeRules) == Set(requirement.rules),
                        measurement.activeRules.count == requirement.rules.count
                    else { throw .coverage(subject.identity) }
                    try Self.validate(measurement)
                }
                let requiredEngines = Set(requirements.map(\.engine))
                guard Set(measurements.map(\.engine)) == requiredEngines else {
                    throw .engines(subject.identity)
                }

                for artifact in subject.artifacts {
                    let engineCoverage = requirements.contains {
                        $0.artifacts.contains(artifact.path)
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
                        if case .findings(let reasons) = measured.verdict, reasons.isEmpty {
                            throw .artifacts(subject.identity)
                        }
                    }
                }
            }
            guard report.measurements.count == commitment.requirements.count else {
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

        private static func validate(_ measurement: Source.Measurement) throws(Error) {
            let files = measurement.files
            let rules = measurement.activeRules
            guard Set(files).count == files.count,
                Set(rules).count == rules.count,
                rules.allSatisfy({ $0.engine == measurement.engine }),
                measurement.observations.count == files.count * rules.count
            else { throw .coverage(measurement.subject.identity) }
            for file in files {
                for rule in rules {
                    let observations = measurement.observations.filter {
                        $0.file == file && $0.rule == rule
                    }
                    guard observations.count == 1, let observation = observations.first else {
                        throw .coverage(measurement.subject.identity)
                    }
                    guard case .measured = observation.coverage else {
                        throw .coverage(measurement.subject.identity)
                    }
                }
            }
            let applicable = Set(
                measurement.observations.compactMap {
                    $0.applicable ? $0.rule : nil
                }
            )
            guard applicable == Set(measurement.applicableRules),
                measurement.applicableRules.count == applicable.count
            else { throw .coverage(measurement.subject.identity) }
            for finding in measurement.suppressions {
                guard rules.contains(finding.rule),
                    files.contains(finding.diagnostic.location.filePath)
                else { throw .coverage(measurement.subject.identity) }
            }
            for repair in measurement.repairs {
                guard rules.contains(repair.rule), files.contains(repair.file) else {
                    throw .coverage(measurement.subject.identity)
                }
            }
            switch measurement.verdict {
            case .clean:
                break
            case .findings(let findings):
                guard !findings.isEmpty,
                    findings.allSatisfy({ finding in
                        rules.contains(finding.rule)
                            && files.contains(finding.diagnostic.location.filePath)
                    })
                else { throw .coverage(measurement.subject.identity) }
            case .unmeasured(let reasons):
                guard !reasons.isEmpty else { throw .coverage(measurement.subject.identity) }
                throw .coverage(measurement.subject.identity)
            case .notRequested:
                throw .coverage(measurement.subject.identity)
            }
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
