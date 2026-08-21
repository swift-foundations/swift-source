extension Source.Repair {
  public enum Postcondition: Hashable, Sendable, JSON.Serializable {
    case file(path: Swift.String, digest: Swift.String)
    case absent(path: Swift.String)

    public static func serialize(_ value: Self) -> JSON {
      switch value {
      case .file(let path, let digest):
        ["state": "file", "path": path.json, "digest": digest.json]
      case .absent(let path):
        ["state": "absent", "path": path.json]
      }
    }

    public static func deserialize(_ json: JSON) throws(JSON.Error) -> Self {
      guard let object = json.dictionary,
        let state = object["state"],
        let path = object["path"]
      else { throw .typeMismatch(expected: "postcondition object", got: "other") }
      switch try Swift.String(json: state) {
      case "file":
        guard let digest = object["digest"] else { throw .missingKey("digest") }
        return try .file(
          path: Swift.String(json: path),
          digest: Swift.String(json: digest)
        )
      case "absent": return try .absent(path: Swift.String(json: path))
      default: throw .typeMismatch(expected: "postcondition state", got: "unknown")
      }
    }
  }
}
