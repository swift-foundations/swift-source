extension Source.Measurement.Verdict: JSON.Serializable {
    public static func serialize(_ value: Self) -> JSON {
        switch value {
        case .clean: ["state": "clean".json]
        case .findings(let findings):
            ["state": "findings".json, "findings": findings.json]
        case .unmeasured(let reasons):
            ["state": "unmeasured".json, "reasons": reasons.json]
        case .notRequested: ["state": "not-requested".json]
        }
    }

    public static func deserialize(_ json: JSON) throws(JSON.Error) -> Self {
        guard let object = json.dictionary else {
            throw .typeMismatch(expected: "object", got: "non-object")
        }
        guard let state = object["state"] else { throw .missingKey("state") }
        switch try Swift.String(json: state) {
        case "clean": return .clean
        case "findings":
            guard let findings = object["findings"] else { throw .missingKey("findings") }
            return try .findings([Source.Finding](json: findings))
        case "unmeasured":
            guard let reasons = object["reasons"] else { throw .missingKey("reasons") }
            return try .unmeasured([Source.Reason](json: reasons))
        case "not-requested": return .notRequested
        default: throw .typeMismatch(expected: "measurement verdict", got: "unknown")
        }
    }
}
