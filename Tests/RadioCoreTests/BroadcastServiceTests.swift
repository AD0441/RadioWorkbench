import Foundation
import Testing
@testable import RadioCore

private func mockSchedule() -> Data {
    Data((0..<100).map { "\(6000+$0);0000-2400;;CHL;TEST \($0);S;SAm;;1;;" }.joined(separator: "\n").utf8)
}
private func cacheFile() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("eibi-test-\(UUID())", isDirectory: true).appendingPathComponent("cache.json") }
private func mockResponse(_ request: URLRequest, data: Data, host: String? = nil) -> (Data,HTTPURLResponse) {
    let url = host.map { URL(string: "https://\($0)/schedule")! } ?? request.url!
    return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Last-Modified":"Sun, 04 Oct 2026 12:53:56 GMT"])!)
}

@Test func broadcastDownloadPersistsSourceAndOfflineCopy() async throws {
    let file = cacheFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let service = BroadcastService(cacheURL: file, resourceDirectory: nil, transport: { request in
        if request.url!.path.hasSuffix("README.TXT") { throw URLError(.notConnectedToInternet) }
        #expect(request.url!.path == "/dx/sked-a26.csv")
        return mockResponse(request, data: mockSchedule())
    })
    let now = ISO8601DateFormatter().date(from: "2026-10-13T06:00:00Z")!
    let snapshot = try await service.download(now: now)
    #expect(snapshot.entries.count == 100)
    #expect(snapshot.fetchedAt == now)
    #expect(snapshot.sourceModifiedAt == ISO8601DateFormatter().date(from: "2026-10-04T12:53:56Z"))
    let reopened = BroadcastService(cacheURL: file, resourceDirectory: nil, transport: { _ in throw URLError(.notConnectedToInternet) })
    #expect(await reopened.cached()?.entries.count == 100)
    let before = try Data(contentsOf: file)
    do { _ = try await reopened.download(now: now); Issue.record("Offline update unexpectedly succeeded") } catch {}
    #expect(try Data(contentsOf: file) == before)
}

@Test func broadcastMalformedResponseCannotReplaceCache() async throws {
    let file = cacheFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let good = BroadcastService(cacheURL: file, resourceDirectory: nil, transport: { request in mockResponse(request, data: mockSchedule()) })
    _ = try await good.download()
    let before = try Data(contentsOf: file)
    let bad = BroadcastService(cacheURL: file, resourceDirectory: nil, transport: { request in
        mockResponse(request, data: Data(String(repeating: "<html>server error</html>", count: 30).utf8))
    })
    do { _ = try await bad.download(); Issue.record("HTML response unexpectedly accepted") } catch {}
    #expect(try Data(contentsOf: file) == before)
}

@Test func broadcastRedirectOutsideSourceIsRejected() async throws {
    let file = cacheFile()
    let service = BroadcastService(cacheURL: file, resourceDirectory: nil, transport: { request in mockResponse(request, data: mockSchedule(), host: "example.org") })
    do { _ = try await service.download(); Issue.record("Unexpected host accepted") } catch {}
    #expect(!FileManager.default.fileExists(atPath: file.path))
}

@Test func broadcastSourceHTTPFallbackWorks() async throws {
    let file = cacheFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let service = BroadcastService(cacheURL: file, resourceDirectory: nil, transport: { request in
        if request.url!.scheme == "https" { throw URLError(.secureConnectionFailed) }
        return mockResponse(request, data: mockSchedule())
    })
    let snapshot = try await service.download()
    #expect(snapshot.sourceURL.scheme == "http")
    #expect(snapshot.entries.count == 100)
}
