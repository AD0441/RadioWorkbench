import Foundation

public actor HFCCScheduleService {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let cacheURL: URL
    private let transport: Transport

    public init(cacheURL: URL? = nil, transport: @escaping Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }) {
        self.cacheURL = cacheURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RadioWorkbench", isDirectory: true).appendingPathComponent("hfcc-cache.json")
        self.transport = transport
    }

    public func cached() -> HFCCScheduleSnapshot? {
        guard let data = try? Data(contentsOf: cacheURL), data.count <= 30_000_000 else { return nil }
        return try? JSONDecoder().decode(HFCCScheduleSnapshot.self, from: data)
    }

    public func download(now: Date = Date()) async throws -> HFCCScheduleSnapshot {
        let season = BroadcastCalendar.season(at: now)
        let url = URL(string: "https://new.hfcc.org/data/\(season)/\(season)allx2.zip")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        request.setValue("RadioWorkbench/0.11 HFCC schedule reader", forHTTPHeaderField: "User-Agent")
        let (archive, response) = try await transport(request)
        guard response.statusCode == 200, response.url?.scheme == "https", response.url?.host == "new.hfcc.org",
              archive.count > 100, archive.count <= 15_000_000,
              archive.prefix(2) == Data([0x50, 0x4b]) else { throw URLError(.badServerResponse) }
        let text = try await Task.detached(priority: .utility) { try Self.scheduleText(from: archive, season: season) }.value
        let snapshot = try HFCCScheduleParser.parse(text, season: season, sourceURL: url, fetchedAt: now)
        guard snapshot.transmissions.count >= 100 else { throw URLError(.cannotParseResponse) }
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: cacheURL, options: .atomic)
        return snapshot
    }

    nonisolated static func scheduleText(from archive: Data, season: String) throws -> String {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("radio-workbench-hfcc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let zip = folder.appendingPathComponent("schedule.zip")
        try archive.write(to: zip, options: .atomic)

        func unzip(_ arguments: [String], maximumBytes: Int) throws -> Data {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = arguments
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()

            var data = Data()
            while data.count <= maximumBytes {
                let remainingIncludingOverflowByte = maximumBytes - data.count + 1
                let chunk = output.fileHandleForReading.readData(ofLength: min(64 * 1024, remainingIncludingOverflowByte))
                guard !chunk.isEmpty else { break }
                data.append(chunk)
            }
            if data.count > maximumBytes {
                if process.isRunning { process.terminate() }
                output.fileHandleForReading.closeFile()
                process.waitUntilExit()
                throw URLError(.dataLengthExceedsMaximum)
            }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw URLError(.cannotDecodeContentData) }
            return data
        }

        let listingData = try unzip(["-Z1", zip.path], maximumBytes: 100_000)
        // The published allx2.zip currently contains A26all00.TXT. Older
        // archives used allx2.txt. Select only a known schedule name, never the
        // first TXT (the archive also contains administrative reference tables).
        let members = String(decoding: listingData, as: UTF8.self).components(separatedBy: .newlines)
        let member = ["\(season)all00.txt", "\(season)allx2.txt"].compactMap { expected in
            members.first { URL(fileURLWithPath: $0).lastPathComponent.caseInsensitiveCompare(expected) == .orderedSame }
        }.first
        guard let member else { throw URLError(.cannotParseResponse) }
        let bytes = try unzip(["-p", zip.path, member], maximumBytes: 50_000_000)
        guard !bytes.isEmpty,
              let text = String(data: bytes, encoding: .isoLatin1) ?? String(data: bytes, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        return text
    }
}
