extension Source.Repair {
    public struct Plan: Sendable, JSON.Serializable {
        public static let schema = 3

        public let subject: Source.Subject.Binding
        public let profile: Source.Profile.Digest
        public let sources: Source.SourceSet.Digest
        public let operations: [Operation]
        public let refusals: [Refusal]
        public let postconditions: [Postcondition]

        public init(
            subject: Source.Subject.Binding,
            profile: Source.Profile.Digest,
            sources: Source.SourceSet.Digest,
            operations: [Operation],
            refusals: [Refusal],
            postconditions: [Postcondition]
        ) {
            self.subject = subject
            self.profile = profile
            self.sources = sources
            self.operations = operations
            self.refusals = refusals
            self.postconditions = postconditions
        }

        public static func serialize(_ value: Self) -> JSON {
            [
                "schema": schema.json,
                "subject": value.subject.json,
                "profile": value.profile.json,
                "sources": value.sources.json,
                "operations": value.operations.json,
                "refusals": value.refusals.json,
                "postconditions": value.postconditions.json,
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
                throw .typeMismatch(expected: "source repair schema 3", got: "other schema")
            }
            return try Self(
                subject: Source.Subject.Binding(json: required("subject")),
                profile: Source.Profile.Digest(json: required("profile")),
                sources: Source.SourceSet.Digest(json: required("sources")),
                operations: [Operation](json: required("operations")),
                refusals: [Refusal](json: required("refusals")),
                postconditions: [Postcondition](json: required("postconditions"))
            )
        }
    }
}
