import Foundation
import CryptoKit
import RadioCore

/// Optional upstream runtime: never redistributed in RadioWorkbench's binary or repository.
enum DSDEngineInstaller {
    static let releaseURL = URL(string: "https://github.com/arancormonk/dsd-neo/releases/download/v2.10.0/dsd-neo-macos-arm64-portable-v2.10.0.dmg")!
    static let sha256 = "260e7aaaa02301dbfce2fb1d7492e3e0be4e64f6f654059e5d52f2c4f5131a58"
    static func install() async throws {
        guard ExternalAudioEngine.dsdSupported else { throw AudioEngineError.unavailable("DSD-neo oficial requiere macOS 26.") }
        let (download, response) = try await URLSession.shared.download(from: releaseURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let size = try download.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 20_000_000 else { throw AudioEngineError.failed("La descarga de DSD-neo no es válida.") }
        defer { try? FileManager.default.removeItem(at: download) }
        let data = try Data(contentsOf: download, options: .mappedIfSafe)
        guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == sha256 else { throw AudioEngineError.failed("La huella de DSD-neo no coincide. No se instaló el motor.") }
        try await Task.detached(priority: .utility) {
            let fm = FileManager.default, temp = fm.temporaryDirectory.appendingPathComponent("RadioWorkbench-engine-\(UUID().uuidString)")
            try fm.createDirectory(at: temp, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: temp) }
            let image = temp.appendingPathComponent("engine.dmg"), mount = temp.appendingPathComponent("mount")
            try fm.copyItem(at: download, to: image); try fm.createDirectory(at: mount, withIntermediateDirectories: true)
            try run("/usr/bin/hdiutil", ["attach", image.path, "-nobrowse", "-readonly", "-mountpoint", mount.path])
            defer { try? run("/usr/bin/hdiutil", ["detach", mount.path]) }
            let root = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("RadioWorkbench/Engines")
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            let staging = root.appendingPathComponent(".install-\(UUID().uuidString)"), destination = root.appendingPathComponent("dsd-neo-2.10.0")
            defer { try? fm.removeItem(at: staging) }
            try fm.copyItem(at: mount.appendingPathComponent("dsd-neo-macos"), to: staging)
            guard fm.isExecutableFile(atPath: staging.appendingPathComponent("bin/dsd-neo").path) else { throw AudioEngineError.failed("El paquete no contiene el motor esperado.") }
            // Preserve the old engine until a complete, verified new copy exists.
            if fm.fileExists(atPath: destination.path) { throw AudioEngineError.failed("DSD-neo ya está instalado. No se sobrescribió.") }
            try fm.moveItem(at: staging, to: destination)
        }.value
    }
    private static func run(_ executable: String, _ arguments: [String]) throws {
        let p = Process(); p.executableURL = URL(fileURLWithPath: executable); p.arguments = arguments
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw AudioEngineError.failed("No se pudo preparar el paquete de DSD-neo (\(p.terminationStatus)).") }
    }
}
