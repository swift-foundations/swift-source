extension Source.Artifact {
    public enum Verdict: Sendable, JSON.Serializable {
        case clean
        case findings([Source.Reason])
        case unmeasured([Source.Reason])

        public static func serialize(_ value: Self) -> JSON {
            switch value {
            case .clean:
                ["status": "clean".json]
            case .findings(let reasons):
                ["status": "findings".json, "reasons": reasons.json]
            case .unmeasured(let reasons):
                ["status": "unmeasured".json, "reasons": reasons.json]
            }
        }

        public static func deserialize(_ json: JSON) throws(JSON.Error) -> Self {
            guard let object = json.dictionary else {
                throw .typeMismatch(expected: "object", got: "non-object")
            }
            guard let status = object["status"] else { throw .missingKey("status") }
            switch try Swift.String(json: status) {
            case "clean": return .clean
            case "findings":
                guard let reasons = object["reasons"] else { throw .missingKey("reasons") }
                return try .findings([Source.Reason](json: reasons))
            case "unmeasured":
                guard let reasons = object["reasons"] else { throw .missingKey("reasons") }
                return try .unmeasured([Source.Reason](json: reasons))
            default:
                throw .typeMismatch(expected: "artifact verdict", got: "unknown status")
            }
        }
    }
}
