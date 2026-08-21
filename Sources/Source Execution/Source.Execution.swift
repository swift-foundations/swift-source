extension Source {
    public struct Execution: Sendable {
        private let drivers: [Engine.ID: Engine.Driver]

        public init(drivers: [Engine.Driver]) throws(Error) {
            var registered: [Engine.ID: Engine.Driver] = [:]
            for driver in drivers {
                guard registered[driver.id] == nil else { throw .duplicate(driver.id) }
                registered[driver.id] = driver
            }
            self.drivers = registered
        }

        public func measure(
            _ subject: Subject,
            profile: Profile,
            engines selected: Set<Engine.ID>? = nil
        ) async -> [Measurement] {
            var measurements: [Measurement] = []
            for engine in profile.engines {
                if let selected, !selected.contains(engine.id) { continue }
                let artifacts = subject.artifacts.filter { engine.artifactKinds.contains($0.kind) }
                guard let driver = drivers[engine.id] else {
                    measurements.append(
                        .init(
                            engine: engine.id,
                            subject: subject,
                            activeRules: engine.rules,
                            applicableRules: [],
                            files: artifacts.map(\.path),
                            verdict: .unmeasured([
                                .init(
                                    code: "missing-driver",
                                    detail: "no driver registered for \(engine.id.token)"
                                )
                            ])
                        )
                    )
                    continue
                }
                measurements.append(await driver.measure(subject, engine))
            }
            return measurements.sorted { $0.engine.token < $1.engine.token }
        }
    }
}
