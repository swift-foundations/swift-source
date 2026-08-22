extension Source {

  public enum Error: Swift.Error, Sendable, Equatable {

    case unsupportedPlatform

    case fileNotFound(path: Swift.String)

    case statFailed(path: Swift.String, errno: Int32)

    case openFailed(path: Swift.String, errno: Int32)

    case readFailed(path: Swift.String, errno: Int32)
  }
}

extension Source.Error: CustomStringConvertible {
  public var description: Swift.String {
    switch self {
    case .unsupportedPlatform:
      return "Source.Loader is not implemented for this platform"

    case .fileNotFound(let path):
      return "Source file not found: \(path)"

    case .statFailed(let path, let errno):
      return "Failed to stat source file '\(path)': errno \(errno)"

    case .openFailed(let path, let errno):
      return "Failed to open source file '\(path)': errno \(errno)"

    case .readFailed(let path, let errno):
      return "Failed to read source file '\(path)': errno \(errno)"
    }
  }
}
