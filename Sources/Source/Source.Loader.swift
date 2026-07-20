// Source.Loader.swift
// swift-source
//
// POSIX-based source file loading.

#if canImport(Darwin)
    internal import Darwin
#elseif canImport(Glibc)
    internal import Glibc
#elseif canImport(Musl)
    internal import Musl
#endif

extension Source {
    /// Loads source files from disk using POSIX system calls.
    ///
    /// `Loader` reads file contents into a `[UInt8]` buffer via `open(2)`, `fstat(2)`,
    /// and `read(2)`. It strips the UTF-8 BOM (`0xEF 0xBB 0xBF`) if present, since
    /// the BOM has no semantic meaning in UTF-8 and would corrupt byte-offset calculations
    /// in downstream lexers.
    ///
    /// ## Platform Support
    ///
    /// Supports Darwin (macOS, iOS) and Linux (glibc, musl). Windows is not yet supported.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let bytes = try Source.Loader.load(contentsOf: "/path/to/file.swift")
    /// // bytes is [UInt8] containing UTF-8 source text (BOM-stripped)
    /// ```
    ///
    /// ## Design Rationale
    ///
    /// Uses POSIX `read()` rather than `mmap()` because source files are typically small
    /// (< 1 MB) and the simpler lifetime model avoids `munmap` concerns. `mmap` can be
    /// introduced later as an optimization for large files without changing the API.
    public enum Loader {}
}

// MARK: - Loading

extension Source.Loader {
    /// Loads the contents of a source file at the given path.
    ///
    /// Opens the file read-only, determines its size via `fstat`, reads the entire
    /// contents into a `[UInt8]` buffer, and closes the file descriptor. If the file
    /// starts with a UTF-8 BOM, those 3 bytes are stripped from the result.
    ///
    /// - Parameter path: Absolute or relative file system path.
    /// - Returns: The file contents as raw UTF-8 bytes (BOM-stripped).
    /// - Throws: `Source.Error` on I/O failure.
    public static func load(
        contentsOf path: Swift.String
    ) throws(Source.Error) -> [UInt8] {
        #if canImport(Darwin) || canImport(Glibc) || canImport(Musl)
            return try _loadPOSIX(contentsOf: path)
        #else
            // Windows / other platforms: not yet supported
            fatalError("Source.Loader is not implemented for this platform")
        #endif
    }
}

// MARK: - POSIX Implementation

#if canImport(Darwin) || canImport(Glibc) || canImport(Musl)
    extension Source.Loader {
        /// POSIX implementation of file loading.
        @usableFromInline
        internal static func _loadPOSIX(
            contentsOf path: Swift.String
        ) throws(Source.Error) -> [UInt8] {
            // Open the file read-only.
            let fd = path.withCString { cPath in
                open(cPath, O_RDONLY)
            }

            guard fd >= 0 else {
                let error = errno
                if error == ENOENT {
                    throw .fileNotFound(path: path)
                }
                throw .openFailed(path: path, errno: error)
            }

            // Ensure the file descriptor is closed on all exit paths.
            defer { close(fd) }

            // Determine file size via fstat.
            var status = stat()
            let fstatResult = fstat(fd, &status)
            guard fstatResult == 0 else {
                throw .statFailed(path: path, errno: errno)
            }

            // `st_size` is `off_t` (a 64-bit signed integer on all supported
            // platforms); on 64-bit targets the conversion to `Int` is lossless.
            // Guard anyway so a hypothetical 32-bit target cannot trap here.
            guard let fileSize = Int(exactly: status.st_size), fileSize >= 0 else {
                throw .statFailed(path: path, errno: EOVERFLOW)
            }

            // Empty file — return immediately.
            if fileSize == 0 {
                return []
            }

            // Read entire file contents.
            let buffer = try _readFully(fd: fd, count: fileSize, path: path)

            // Strip UTF-8 BOM if present.
            return _stripBOM(from: buffer)
        }

        /// Reads up to `count` bytes from `fd`, accumulating across multiple
        /// `read(2)` calls.
        ///
        /// A single `read(2)` may legally return fewer bytes than requested
        /// (pipes, network filesystems, signal interruption). This loop:
        /// - accumulates until `count` bytes are read or EOF is reached,
        /// - retries reads interrupted by signals (`EINTR`),
        /// - captures `errno` only when `read` actually returns `-1`,
        /// - on early EOF returns the bytes actually read (the file may have
        ///   been truncated between `fstat` and `read`).
        @usableFromInline
        internal static func _readFully(
            fd: Int32,
            count: Int,
            path: Swift.String
        ) throws(Source.Error) -> [UInt8] {
            var buffer = [UInt8](repeating: 0, count: count)
            var totalRead = 0

            while totalRead < count {
                let bytesRead = buffer.withUnsafeMutableBufferPointer { pointer in
                    read(fd, pointer.baseAddress! + totalRead, count - totalRead)
                }

                if bytesRead > 0 {
                    totalRead += bytesRead
                } else if bytesRead == 0 {
                    // Early EOF — return the bytes actually read.
                    buffer.removeLast(count - totalRead)
                    return buffer
                } else {
                    let error = errno
                    if error == EINTR {
                        continue
                    }
                    throw .readFailed(path: path, errno: error)
                }
            }

            return buffer
        }

        /// Strips the UTF-8 BOM (0xEF, 0xBB, 0xBF) from the start of the buffer.
        ///
        /// The BOM is a legacy marker with no semantic meaning in UTF-8. Removing it
        /// ensures byte offsets in the lexer correspond directly to source positions.
        @usableFromInline
        internal static func _stripBOM(from buffer: [UInt8]) -> [UInt8] {
            if buffer.count >= 3,
                buffer[0] == 0xEF,
                buffer[1] == 0xBB,
                buffer[2] == 0xBF
            {
                return Array(buffer.dropFirst(3))
            }
            return buffer
        }
    }
#endif
