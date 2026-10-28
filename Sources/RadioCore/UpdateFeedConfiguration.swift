import Foundation

public struct UpdateFeedConfiguration: Sendable {
    public let feed: URL
    public let publicKey: String
    public init?(feed: String?, publicKey: String?) {
        guard let feed, let url = URL(string: feed), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, let publicKey,
              Data(base64Encoded: publicKey)?.count == 32 else { return nil }
        self.feed = url; self.publicKey = publicKey
    }
}
