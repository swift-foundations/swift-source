extension Source {
    public struct Report: Sendable, JSON.Serializable {
        public static let schema = 4

        public let scope: Scope
        public let profile: Profile.Digest
        public let subjects: [Subject]
        public let references: [Reason]
        public let measurements: [Measurement]

        public init(
            scope: Scope,
            profile: Profile.Digest,
            subjects: [Subject],
            references: [Reason],
            measurements: [Measurement]
        ) {
            self.scope = scope
            self.profile = profile
            self.subjects = subjects.sorted { $0.identity < $1.identity }
            self.references = references.sorted { ($0.code, $0.detail) < ($1.code, $1.detail) }
            self.measurements = measurements.sorted {
                ($0.subject.identity, $0.engine.token) <
                    ($1.subject.identity, $1.engine.token)
            }
        }

        public static func serialize(_ value: Self) -> JSON {
            [
                "schema": schema.json,
                "scope": value.scope.json,
                "profile": value.profile.json,
                "subjects": value.subjects.json,
                "references": value.references.json,
                "measurements": value.measurements.json,
            ]
        }

        public static func deserialize(_ json: JSON) throws(JSON.Error) -> Self {
            guard let object = json.dictionary else {
                throw .typeMismatch(expected: "object", got: "non-object")
            }
            func required(_ key: Swift.String) throws(JSON.Error) -> JSON {
                guard let value = object[key] else { throw .missingKey(key) }
                return value
            }
            guard try Swift.Int(json: required("schema")) == schema else {
                throw .typeMismatch(expected: "source report schema 4", got: "other schema")
            }
            return try Self(
                scope: Scope(json: required("scope")),
                profile: Profile.Digest(json: required("profile")),
                subjects: [Subject](json: required("subjects")),
                references: [Reason](json: required("references")),
                measurements: [Measurement](json: required("measurements"))
            )
        }
    }
}
