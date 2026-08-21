extension Source.Artifact {
    public struct Evidence: Sendable, JSON.Serializable {
        public let subject: Swift.String
        public let artifact: Source.Artifact
        public let predicate: Source.Rule.ID
        public let verdict: Verdict

        public init(
            subject: Swift.String,
            artifact: Source.Artifact,
            predicate: Source.Rule.ID,
            verdict: Verdict
        ) {
            self.subject = subject
            self.artifact = artifact
            self.predicate = predicate
            self.verdict = verdict
        }

        public static func serialize(_ value: Self) -> JSON {
            [
                "subject": value.subject.json,
                "artifact": value.artifact.json,
                "predicate": value.predicate.json,
                "verdict": value.verdict.json,
            ]
        }

        public static func deserialize(_ json: JSON) throws(JSON.Error) -> Self {
            guard let object = json.dictionary else {
                throw .typeMismatch(expected: "object", got: "non-object")
            }
            guard Set(object.keys) == ["subject", "artifact", "predicate", "verdict"] else {
                throw .typeMismatch(expected: "artifact evidence keys", got: "foreign keys")
            }
            func required(_ key: Swift.String) throws(JSON.Error) -> JSON {
                guard let value = object[key] else { throw .missingKey(key) }
                return value
            }
            return try Self(
                subject: Swift.String(json: required("subject")),
                artifact: Source.Artifact(json: required("artifact")),
                predicate: Source.Rule.ID(json: required("predicate")),
                verdict: Verdict(json: required("verdict"))
            )
        }
    }
}
