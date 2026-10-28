import Foundation
import CryptoKit

public struct LibraryStorageUsage: Sendable {
    public var audioBytes: Int64 = 0
    public var iqBytes: Int64 = 0
    public var files = 0
    public var total: Int64 { audioBytes + iqBytes }
}

/// Only the two owned libraries are copied; decoder engines, caches and signing keys are excluded.
public actor LibraryMaintenance {
    public init() {}
    public func usage(root: URL) throws -> LibraryStorageUsage {
        var result = LibraryStorageUsage()
        for name in ["Recepciones", "SigMF"] {
            for file in try regularFiles(in: root.appendingPathComponent(name)) {
                let size = Int64(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
                if name == "Recepciones" { result.audioBytes += size } else { result.iqBytes += size }
                result.files += 1
            }
        }
        return result
    }
    public func copyLibraries(from source: URL, to destination: URL) throws {
        let source = source.resolvingSymlinksInPath().standardizedFileURL
        let destination = destination.resolvingSymlinksInPath().standardizedFileURL
        guard source != destination, !destination.path.hasPrefix(source.path + "/"), !source.path.hasPrefix(destination.path + "/") else { throw PreferencesError.unsafeFolder }
        let manager = FileManager.default
        for name in ["Recepciones", "SigMF"] where manager.fileExists(atPath: destination.appendingPathComponent(name).path) { throw PreferencesError.destinationNotEmpty }
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)
        let stage = destination.appendingPathComponent(".copy-\(UUID())", isDirectory: true)
        try manager.createDirectory(at: stage, withIntermediateDirectories: false)
        var published: [URL] = [], committed = false
        defer {
            try? manager.removeItem(at: stage)
            if !committed { for url in published { try? manager.removeItem(at: url) } }
        }
        for name in ["Recepciones", "SigMF"] {
            let original = source.appendingPathComponent(name)
            guard manager.fileExists(atPath: original.path) else { continue }
            let target = stage.appendingPathComponent(name)
            try manager.createDirectory(at: target, withIntermediateDirectories: true)
            for file in try regularFiles(in: original) {
                try Task.checkCancellation()
                let canonical = file.resolvingSymlinksInPath().standardizedFileURL
                let canonicalRoot = original.resolvingSymlinksInPath().standardizedFileURL
                guard canonical.path.hasPrefix(canonicalRoot.path + "/") else { throw PreferencesError.unsafeFolder }
                let relative = canonical.pathComponents.dropFirst(canonicalRoot.pathComponents.count).joined(separator: "/")
                guard !relative.isEmpty else { throw PreferencesError.unsafeFolder }
                let output = target.appendingPathComponent(relative)
                try manager.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                try copyAndVerify(file, to: output)
            }
            try Task.checkCancellation()
            let final = destination.appendingPathComponent(name)
            try manager.moveItem(at: target, to: final); published.append(final)
        }
        committed = true
    }
    public func backup(root: URL, destination: URL, settings: Data, inputProfiles: URL? = nil) throws -> URL {
        let fm = FileManager.default
        let stage = fm.temporaryDirectory.appendingPathComponent("rwb-backup-\(UUID())", isDirectory: true)
        defer { try? fm.removeItem(at: stage) }
        let payload = stage.appendingPathComponent("RadioWorkbench-Backup")
        try copyLibraries(from: root, to: payload)
        try settings.write(to: payload.appendingPathComponent("preferences.json"), options: .atomic)
        if let profiles = inputProfiles, fm.fileExists(atPath: profiles.path) { try copyAndVerify(profiles, to: payload.appendingPathComponent("InputProfiles.json")) }
        guard !fm.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["--norsrc","--noextattr","-c","-k","--keepParent",payload.path,destination.path]
        try Task.checkCancellation(); try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { try? fm.removeItem(at: destination); throw CocoaError(.fileWriteUnknown) }
        return destination
    }
    private func regularFiles(in directory: URL) throws -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }
        let keys: [URLResourceKey] = [.isSymbolicLinkKey,.isRegularFileKey,.isDirectoryKey]
        guard try directory.resourceValues(forKeys: Set(keys)).isSymbolicLink != true else { throw PreferencesError.unsafeFolder }
        var failure: (any Error)?
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: keys, errorHandler: { _, error in failure = error; return false }) else { throw CocoaError(.fileReadUnknown) }
        var files: [URL] = []
        for case let file as URL in enumerator {
            try Task.checkCancellation()
            let info = try file.resourceValues(forKeys: Set(keys))
            guard info.isSymbolicLink != true else { throw PreferencesError.unsafeFolder }
            if info.isRegularFile == true { files.append(file) }
        }
        if let failure { throw failure }
        return files
    }
    private func copyAndVerify(_ input: URL, to output: URL) throws {
        let source = try FileHandle(forReadingFrom: input); defer { try? source.close() }
        guard FileManager.default.createFile(atPath: output.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let target = try FileHandle(forWritingTo: output); defer { try? target.close() }
        var expected = SHA256()
        while let data = try source.read(upToCount: 1_048_576), !data.isEmpty { try Task.checkCancellation(); expected.update(data: data); try target.write(contentsOf: data) }
        try target.synchronize()
        let read = try FileHandle(forReadingFrom: output); defer { try? read.close() }
        var actual = SHA256()
        while let data = try read.read(upToCount: 1_048_576), !data.isEmpty { try Task.checkCancellation(); actual.update(data: data) }
        guard expected.finalize() == actual.finalize() else { throw CocoaError(.fileReadCorruptFile) }
    }
}

public enum AppSupportPaths {
    public static var inputProfiles: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("RadioWorkbench/InputProfiles.json") }
}
