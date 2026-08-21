extension Source.Artifact {
    public enum Provenance: Hashable, Sendable, JSON.Serializable {
        case authored
        case generated(owner: Swift.String)

        public static func serialize(_ value: Self) -> JSON {
            switch value {
            case .authored:
                ["status": "authored".json]
            case .generated(let owner):
                ["status": "generated".json, "owner": owner.json]
            }
        }

        public static func deserialize(_ json: JSON) throws(JSON.Error) -> Self {
            guard let object = json.dictionary else {
                throw .typeMismatch(expected: "object", got: "non-object")
            }
            guard let status = object["status"] else { throw .missingKey("status") }
            switch try Swift.String(json: status) {
            case "authored":
                guard object["owner"] == nil else {
                    throw .typeMismatch(expected: "authored provenance", got: "owner")
                }
                return .authored
            case "generated":
                guard let owner = object["owner"] else { throw .missingKey("owner") }
                return .generated(owner: try Swift.String(json: owner))
            default:
                throw .typeMismatch(expected: "authored or generated", got: "other status")
            }
        }
    }
}
