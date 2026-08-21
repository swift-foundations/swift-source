extension Source.Measurement: JSON.Serializable {
    public static func serialize(_ value: Self) -> JSON {
        [
            "engine": value.engine.json,
            "subject": value.subject.json,
            "activeRules": value.activeRules.json,
            "applicableRules": value.applicableRules.json,
            "files": value.files.json,
            "verdict": value.verdict.json,
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
        return try Self(
            engine: Source.Engine.ID(json: required("engine")),
            subject: Source.Subject(json: required("subject")),
            activeRules: [Source.Rule.ID](json: required("activeRules")),
            applicableRules: [Source.Rule.ID](json: required("applicableRules")),
            files: [Swift.String](json: required("files")),
            verdict: Verdict(json: required("verdict"))
        )
    }
}
