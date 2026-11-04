import Foundation

/// A version hint only. The updater verifies all installation metadata on GitHub.
final class ReleaseChannel {
    static let url = URL(string: "https://poby-study-room-default-rtdb.asia-southeast1.firebasedatabase.app/releaseChannel/stable.json")!
    private var task: Task<Void, Never>?
    private let session = URLSession(configuration: .default)

    @MainActor func start(_ found: @escaping (String) -> Void) {
        task = Task { @MainActor in
            var delay: UInt64 = 1
            while !Task.isCancelled {
                do {
                    var request = URLRequest(url: Self.url)
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    let (bytes, response) = try await session.bytes(for: request)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                    for try await line in bytes.lines {
                        if Task.isCancelled { return }
                        guard line.hasPrefix("data: "), let json = String(line.dropFirst(6)).data(using: .utf8),
                              let event = try JSONSerialization.jsonObject(with: json) as? [String: Any],
                              event["path"] as? String == "/", let tag = event["data"] as? String,
                              tag.range(of: "^v[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil else { continue }
                        delay = 1
                        found(tag)
                    }
                } catch { }
                do { try await Task.sleep(nanoseconds: delay * 1_000_000_000) } catch { return }
                delay = min(60, delay * 2)
            }
        }
    }

    func stop() { task?.cancel(); session.invalidateAndCancel() }
    deinit { stop() }
}
