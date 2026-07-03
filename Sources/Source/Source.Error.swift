// Source.Error.swift
// swift-source
//
// Typed error for source file I/O failures.

extension Source {
    /// Error type for source file loading operations.
    ///
    /// All throwing functions in `Source.Loader` use typed throws with this error,
    /// per [API-ERR-001].
    ///
    /// ## Cases
    ///
    /// - ``fileNotFound``: The file does not exist at the given path.
    /// - ``readFailed``: The file was opened but reading failed.
    /// - ``openFailed``: The file could not be opened (permissions, etc.).
    public enum Error: Swift.Error, Sendable, Equatable {
        /// The file does not exist at the specified path.
        case fileNotFound(path: Swift.String)

        /// The file could not be opened.
        ///
        /// - Parameters:
        ///   - path: The file path that failed to open.
        ///   - errno: The POSIX errno value.
        case openFailed(path: Swift.String, errno: Int32)

        /// Reading the file contents failed after a successful open.
        ///
        /// - Parameters:
        ///   - path: The file path that failed to read.
        ///   - errno: The POSIX errno value.
        case readFailed(path: Swift.String, errno: Int32)
    }
}

// MARK: - CustomStringConvertible

extension Source.Error: CustomStringConvertible {
    public var description: Swift.String {
        switch self {
        case .fileNotFound(let path):
            return "Source file not found: \(path)"

        case .openFailed(let path, let errno):
            return "Failed to open source file '\(path)': errno \(errno)"

        case .readFailed(let path, let errno):
            return "Failed to read source file '\(path)': errno \(errno)"
        }
    }
}
