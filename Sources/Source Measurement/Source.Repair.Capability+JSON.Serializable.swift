extension Source.Repair.Capability: JSON.Serializable {
    public static func serialize(_ value: Self) -> JSON {
        switch value {
        case .automatic: ["state": "automatic".json]
        case .guarded: ["state": "guarded".json]
        case .transactional: ["state": "transactional".json]
        case .unavailable(let reason):
            ["state": "unavailable".json, "reason": reason.json]
        }
    }

    public static func deserialize(_ json: JSON) throws(JSON.Error) -> Self {
        guard let object = json.dictionary else {
            throw .typeMismatch(expected: "object", got: "non-object")
        }
        guard let state = object["state"] else { throw .missingKey("state") }
        switch try Swift.String(json: state) {
        case "automatic": return .automatic
        case "guarded": return .guarded
        case "transactional": return .transactional
        case "unavailable":
            guard let reason = object["reason"] else { throw .missingKey("reason") }
            return try .unavailable(Source.Reason(json: reason))
        default: throw .typeMismatch(expected: "repair capability", got: "unknown")
        }
    }
}
