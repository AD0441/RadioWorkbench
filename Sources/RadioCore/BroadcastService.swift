import Foundation

public actor BroadcastService {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private struct EmbeddedMetadata: Decodable {
        let season: String
        let sourceURL: URL
        let fetchedAt: String
        let sourceModifiedAt: String
    }
    private let cacheURL: URL
    private let resourceDirectory: URL?
    private let transport: Transport
    public init(cacheURL: URL? = nil, resourceDirectory: URL? = Bundle.main.resourceURL?.appendingPathComponent("EiBi"), transport: @escaping Transport = { request in
        let (data,response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data,http)
    }) {
        self.cacheURL = cacheURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RadioWorkbench", isDirectory: true).appendingPathComponent("eibi-cache.json")
        self.resourceDirectory = resourceDirectory; self.transport = transport
    }
    public func cached() -> BroadcastSnapshot? {
        if let data = try? Data(contentsOf: cacheURL), data.count < 20_000_000,
              let snapshot = try? JSONDecoder().decode(BroadcastSnapshot.self, from: data),
              !snapshot.entries.isEmpty { return snapshot }
        guard let resourceDirectory else { return nil }
        let metadataURL = resourceDirectory.appendingPathComponent("metadata.json")
        guard
              let bytes = try? Data(contentsOf: metadataURL), let meta = try? JSONDecoder().decode(EmbeddedMetadata.self, from: bytes),
              let csv = try? Data(contentsOf: resourceDirectory.appendingPathComponent("sked-\(meta.season).csv")), let text = BroadcastParser.text(csv),
              let codes = try? Data(contentsOf: resourceDirectory.appendingPathComponent("README.TXT")), let codeText = BroadcastParser.text(codes),
              let fetchedAt = ISO8601DateFormatter().date(from: meta.fetchedAt) else { return nil }
        let parsed = BroadcastParser.csv(text)
        return BroadcastSnapshot(entries: parsed.entries, reference: BroadcastReference.parse(codeText), season: meta.season, sourceURL: meta.sourceURL, fetchedAt: fetchedAt, sourceModifiedAt: ISO8601DateFormatter().date(from: meta.sourceModifiedAt), skippedRows: parsed.skipped)
    }
    public func download(now: Date = Date()) async throws -> BroadcastSnapshot {
        let season = BroadcastCalendar.season(at: now)
        var lastError: Error = URLError(.cannotConnectToHost)
        for scheme in ["https", "http"] {
            let url = URL(string: "\(scheme)://www.eibispace.de/dx/sked-\(season).csv")!
            do {
                let (data, response) = try await fetch(url, limit: 5_000_000)
                guard let text = BroadcastParser.text(data) else { throw URLError(.cannotDecodeContentData) }
                let parsed = BroadcastParser.csv(text)
                guard parsed.entries.count >= 100, parsed.skipped < parsed.entries.count else { throw URLError(.cannotParseResponse) }
                var reference = cached()?.reference ?? BroadcastReference()
                if let (codes, _) = try? await fetch(URL(string: "\(scheme)://www.eibispace.de/dx/README.TXT")!, limit: 2_000_000),
                   let codeText = BroadcastParser.text(codes) {
                    let updated = BroadcastReference.parse(codeText)
                    if updated.countries.count > 100 && updated.languages.count > 100 { reference = updated }
                }
                let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                let modified = response.value(forHTTPHeaderField: "Last-Modified").flatMap(formatter.date(from:))
                let snapshot = BroadcastSnapshot(entries: parsed.entries, reference: reference, season: season, sourceURL: url, fetchedAt: now, sourceModifiedAt: modified, skippedRows: parsed.skipped)
                try save(snapshot)
                return snapshot
            } catch is CancellationError { throw CancellationError() }
            catch { lastError = error }
        }
        throw lastError
    }
    public func importCSV(_ url: URL) throws -> BroadcastSnapshot {
        let data = try Data(contentsOf: url)
        guard data.count < 5_000_000, let text = BroadcastParser.text(data) else { throw URLError(.cannotDecodeContentData) }
        let parsed = BroadcastParser.csv(text)
        guard !parsed.entries.isEmpty else { throw URLError(.cannotParseResponse) }
        let snapshot = BroadcastSnapshot(entries: parsed.entries, reference: cached()?.reference ?? BroadcastReference(), season: "importada", sourceURL: url, fetchedAt: Date(), sourceModifiedAt: nil, skippedRows: parsed.skipped)
        try save(snapshot); return snapshot
    }
    private func save(_ snapshot: BroadcastSnapshot) throws {
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: cacheURL, options: .atomic)
    }
    private func fetch(_ url: URL, limit: Int) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("RadioWorkbench/0.5 EiBi schedule reader", forHTTPHeaderField: "User-Agent")
        let (data, http) = try await transport(request)
        guard http.statusCode == 200,
              data.count <= limit, data.count >= 100,
              http.url?.host == "www.eibispace.de" || http.url?.host == "eibispace.de" else { throw URLError(.badServerResponse) }
        return (data,http)
    }
}
