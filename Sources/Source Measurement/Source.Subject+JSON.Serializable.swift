extension Source.Subject: JSON.Serializable {
    public static func serialize(_ value: Self) -> JSON {
        [
            "identity": value.identity.json,
            "root": value.root.json,
            "files": value.files.json,
        ]
    }

    public static func deserialize(_ json: JSON) throws(JSON.Error) -> Self {
        guard let object = json.dictionary else {
            throw .typeMismatch(expected: "object", got: "non-object")
        }
        guard let identity = object["identity"] else { throw .missingKey("identity") }
        guard let root = object["root"] else { throw .missingKey("root") }
        guard let files = object["files"] else { throw .missingKey("files") }
        return try Self(
            identity: Swift.String(json: identity),
            root: Swift.String(json: root),
            files: [Swift.String](json: files)
        )
    }
}
