import Foundation
import Darwin

public enum AtomicFileCopy {
    /// FileManager streams the copy without loading an entire recording into
    /// memory. Publish with a same-directory rename, preserving any old output
    /// if staging fails. Call from a background task for large recordings.
    public static func copy(from source: URL, to destination: URL) throws {
        guard source.isFileURL, destination.isFileURL else { throw CocoaError(.fileWriteUnsupportedScheme) }
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".RadioWorkbench-export-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.copyItem(at: source, to: staging)
        let result = staging.withUnsafeFileSystemRepresentation { temporary in
            destination.withUnsafeFileSystemRepresentation { output in
                rename(temporary!, output!)
            }
        }
        if result != 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
