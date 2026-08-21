extension Source.Repair.Evidence.Disposition: JSON.Serializable {
    public static func serialize(_ value: Self) -> JSON {
        switch value {
        case .unchanged: return ["status": "unchanged"]
        case .edits(let edits): return ["status": "edits", "edits": edits.json]
        case .refused(let reason): return ["status": "refused", "reason": reason.json]
        }
    }

    public static func deserialize(_ json: JSON) throws(JSON.Error) -> Self {
        guard let object = json.dictionary, let status = object["status"] else {
            throw .typeMismatch(expected: "repair disposition object", got: "other")
        }
        switch try Swift.String(json: status) {
        case "unchanged": return .unchanged
        case "edits":
            guard let edits = object["edits"] else { throw .missingKey("edits") }
            return try .edits([Source.Repair.Evidence.Edit](json: edits))
        case "refused":
            guard let reason = object["reason"] else { throw .missingKey("reason") }
            return try .refused(Source.Reason(json: reason))
        default: throw .typeMismatch(expected: "repair disposition", got: "unknown")
        }
    }
}
