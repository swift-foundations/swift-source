extension Source.Repair.Evidence.Edit: JSON.Serializable {
    public static func serialize(_ value: Self) -> JSON {
        switch value {
        case .rewrite(let path, let contents):
            return ["operation": "rewrite", "path": path.json, "contents": contents.json]
        case .create(let path, let contents):
            return ["operation": "create", "path": path.json, "contents": contents.json]
        case .move(let from, let to):
            return ["operation": "move", "from": from.json, "to": to.json]
        case .delete(let path):
            return ["operation": "delete", "path": path.json]
        }
    }

    public static func deserialize(_ json: JSON) throws(JSON.Error) -> Self {
        guard let object = json.dictionary, let operation = object["operation"] else {
            throw .typeMismatch(expected: "repair edit object", got: "other")
        }
        func string(_ key: Swift.String) throws(JSON.Error) -> Swift.String {
            guard let value = object[key] else { throw .missingKey(key) }
            return try Swift.String(json: value)
        }
        switch try Swift.String(json: operation) {
        case "rewrite": return try .rewrite(path: string("path"), contents: string("contents"))
        case "create": return try .create(path: string("path"), contents: string("contents"))
        case "move": return try .move(from: string("from"), to: string("to"))
        case "delete": return try .delete(path: string("path"))
        default: throw .typeMismatch(expected: "repair operation", got: "unknown")
        }
    }
}
