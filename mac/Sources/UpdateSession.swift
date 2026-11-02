import Foundation

struct UpdateSession: Codable {
    let state: String
    let subject: String
    let seconds: Double

    func encode() throws -> String { String(decoding: try JSONEncoder().encode(self), as: UTF8.self) }
    static func parse(_ raw: String) -> UpdateSession? {
        guard let saved = try? JSONDecoder().decode(Self.self, from: Data(raw.utf8)),
              ["studying", "paused"].contains(saved.state), !Records.cleanSubject(saved.subject).isEmpty,
              saved.seconds.isFinite, saved.seconds >= 0, saved.seconds < 400_000_000_000 else { return nil }
        return Self(state: saved.state, subject: Records.cleanSubject(saved.subject), seconds: saved.seconds)
    }
}
