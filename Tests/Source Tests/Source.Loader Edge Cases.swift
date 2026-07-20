// Source.Loader Edge Cases.swift
// swift-source
//
// Regression tests for short-read and EOF handling (fable-448 F-001).

import Testing

@testable import Source

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

extension Source.Loader.Test {
    @Suite
    struct `Edge Case` {
        @Test
        func `read Fully Returns Bytes Actually Read On Early EOF`() throws {
            // A pipe with 4 buffered bytes and a closed write end delivers a
            // short read (4 of 8 requested) followed by EOF. The loader must
            // return the 4 bytes actually read — not a spurious .readFailed
            // carrying a stale errno.
            var fds: [Int32] = [-1, -1]
            let pipeResult = fds.withUnsafeMutableBufferPointer { pointer in
                pipe(pointer.baseAddress)
            }
            try #require(pipeResult == 0)
            let readEnd = fds[0]
            let writeEnd = fds[1]
            defer { close(readEnd) }

            let payload: [UInt8] = [0x41, 0x42, 0x43, 0x44]  // "ABCD"
            let written = payload.withUnsafeBufferPointer { pointer in
                write(writeEnd, pointer.baseAddress, pointer.count)
            }
            close(writeEnd)
            try #require(written == payload.count)

            // Poison errno so a stale-errno .readFailed is distinguishable.
            errno = EIO

            let bytes = try Source.Loader._readFully(fd: readEnd, count: 8, path: "<pipe>")
            #expect(bytes == payload)
        }

        @Test
        func `read Fully Returns Full Buffer When All Bytes Available`() throws {
            var fds: [Int32] = [-1, -1]
            let pipeResult = fds.withUnsafeMutableBufferPointer { pointer in
                pipe(pointer.baseAddress)
            }
            try #require(pipeResult == 0)
            let readEnd = fds[0]
            let writeEnd = fds[1]
            defer { close(readEnd) }

            let payload: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
            let written = payload.withUnsafeBufferPointer { pointer in
                write(writeEnd, pointer.baseAddress, pointer.count)
            }
            close(writeEnd)
            try #require(written == payload.count)

            let bytes = try Source.Loader._readFully(fd: readEnd, count: 8, path: "<pipe>")
            #expect(bytes == payload)
        }

        @Test
        func `read Fully Throws Read Failed With Real Errno On Read Error`() throws {
            // read(2) on a descriptor opened write-only fails with EBADF;
            // the thrown error must carry that errno, captured at the failing
            // read call — not an unrelated stale value.
            var fds: [Int32] = [-1, -1]
            let pipeResult = fds.withUnsafeMutableBufferPointer { pointer in
                pipe(pointer.baseAddress)
            }
            try #require(pipeResult == 0)
            let readEnd = fds[0]
            let writeEnd = fds[1]
            defer {
                close(readEnd)
                close(writeEnd)
            }

            #expect(throws: Source.Error.readFailed(path: "<pipe>", errno: EBADF)) {
                try Source.Loader._readFully(fd: writeEnd, count: 4, path: "<pipe>")
            }
        }
    }
}
