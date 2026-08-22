#if canImport(Darwin)
  internal import Darwin
#elseif canImport(Glibc)
  internal import Glibc
#elseif canImport(Musl)
  internal import Musl
#endif

extension Source {

  public enum Loader {}
}

extension Source.Loader {

  public static func load(
    contentsOf path: Swift.String
  ) throws(Source.Error) -> [UInt8] {
    #if canImport(Darwin) || canImport(Glibc) || canImport(Musl)
      return try _loadPOSIX(contentsOf: path)
    #else

      throw .unsupportedPlatform
    #endif
  }
}

#if canImport(Darwin) || canImport(Glibc) || canImport(Musl)
  extension Source.Loader {

    @usableFromInline
    internal static func _loadPOSIX(
      contentsOf path: Swift.String
    ) throws(Source.Error) -> [UInt8] {

      let fd = path.withCString { cPath in
        unsafe open(cPath, O_RDONLY)
      }

      guard fd >= 0 else {
        let error = errno
        if error == ENOENT {
          throw .fileNotFound(path: path)
        }
        throw .openFailed(path: path, errno: error)
      }

      defer { close(fd) }

      var status = stat()
      let fstatResult = unsafe fstat(fd, &status)
      guard fstatResult == 0 else {
        throw .statFailed(path: path, errno: errno)
      }

      guard let fileSize = Int(exactly: status.st_size), fileSize >= 0 else {
        throw .statFailed(path: path, errno: EOVERFLOW)
      }

      if fileSize == 0 {
        return []
      }

      let buffer = try _readFully(fd: fd, count: fileSize, path: path)

      return _stripBOM(from: buffer)
    }

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
          unsafe read(fd, pointer.baseAddress! + totalRead, count - totalRead)
        }

        if bytesRead > 0 {
          totalRead += bytesRead
        } else if bytesRead == 0 {

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

  }
#endif

extension Source.Loader {

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
