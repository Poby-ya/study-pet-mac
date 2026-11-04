import AppKit
import CryptoKit

struct UpdateRelease {
    static let root = "https://github.com/Poby-ya/study-pet-releases/releases/download/"
    let tag: String
    let version: [Int]
    let url: URL
    let hash: String
    let size: Int

    static func version(_ value: String) -> [Int]? {
        guard value.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil else { return nil }
        let parts = value.split(separator: ".").compactMap { Int($0) }
        return parts.count == 3 ? parts : nil
    }

    static func parse(_ json: Data) throws -> UpdateRelease {
        guard let data = try JSONSerialization.jsonObject(with: json) as? [String: Any],
              let tag = data["tag_name"] as? String, tag.hasPrefix("v"), let version = version(String(tag.dropFirst())),
              data["draft"] as? Bool != true, data["prerelease"] as? Bool != true,
              let assets = data["assets"] as? [[String: Any]] else { throw RoomError("업데이트 버전 정보를 확인하지 못했어요.") }
        let matches = assets.filter { $0["name"] as? String == "StudyPet-mac.zip" }
        guard matches.count == 1, let asset = matches.first,
              let address = asset["browser_download_url"] as? String, address == root + tag + "/StudyPet-mac.zip",
              let url = URL(string: address), let digest = asset["digest"] as? String,
              digest.range(of: "^sha256:[a-fA-F0-9]{64}$", options: .regularExpression) != nil,
              let size = asset["size"] as? Int, size > 0, size <= 100_000_000 else { throw RoomError("업데이트 파일의 검증 정보를 확인하지 못했어요.") }
        return UpdateRelease(tag: tag, version: version, url: url, hash: String(digest.dropFirst(7)).lowercased(), size: size)
    }
}

// No Firebase credentials or cookies are sent to the release service.
final class UpdateRedirects: NSObject, URLSessionTaskDelegate {
    static func allowed(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil && (url.port == nil || url.port == 443) &&
            ["github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"].contains(url.host ?? "")
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(Self.allowed) == true ? request : nil)
    }
}

final class Updater {
    static var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0" }
    static var errorURL: URL { Records.folder.appendingPathComponent("update-error.txt") }
    private(set) var release: UpdateRelease?
    private var checkAgain = false
    private(set) var checking = false
    private(set) var installing = false
    private(set) var status = "새 버전을 자동으로 확인합니다."
    var changed: (() -> Void)?
    var availabilityChanged: ((Bool) -> Void)?
    var found: ((String) -> Void)?
    var available: Bool { release.map { (UpdateRelease.version(Self.current) ?? [0, 0, 0]).lexicographicallyPrecedes($0.version) } ?? false }

    func check() {
        guard !installing else { return }
        if checking { checkAgain = true; return }
        checking = true
        status = "업데이트 확인 중…"
        changed?()
        Task { @MainActor in
            defer { checking = false; changed?(); if checkAgain { checkAgain = false; check() } }
            do {
                if FileManager.default.fileExists(atPath: Self.errorURL.path) {
                    status = try String(contentsOf: Self.errorURL, encoding: .utf8)
                    try FileManager.default.removeItem(at: Self.errorURL)
                    return
                }
                var request = URLRequest(url: URL(string: "https://api.github.com/repos/Poby-ya/study-pet-releases/releases/latest")!, timeoutInterval: 20)
                request.setValue("StudyPet/" + Self.current, forHTTPHeaderField: "User-Agent")
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw RoomError("릴리스를 확인하지 못했어요.") }
                release = try UpdateRelease.parse(data)
                availabilityChanged?(available)
                status = available ? "새 버전 \(release!.tag)을 설치할 수 있어요." : "최신 버전을 사용하고 있어요."
                if available, Settings.get("updateNotified") != release!.tag {
                    try Settings.set("updateNotified", release!.tag)
                    found?(release!.tag)
                }
            } catch { status = "업데이트를 확인하지 못했어요. 인터넷 연결을 확인하고 다시 눌러 주세요." }
        }
    }

    struct Prepared { let script: URL; let zip: URL; let hash: String }

    @MainActor func prepare() async throws -> Prepared {
        guard available, !installing, let release else { throw RoomError("먼저 업데이트를 확인해 주세요.") }
        installing = true
        status = "새 버전을 받는 중… 공부는 계속할 수 있어요."
        changed?()
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("StudyPet-update-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let zip = work.appendingPathComponent("StudyPet-mac.zip")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 180
        let session = URLSession(configuration: config, delegate: UpdateRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (download, response) = try await session.download(from: release.url)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let finalURL = response.url, UpdateRedirects.allowed(finalURL) else { throw RoomError("업데이트를 받지 못했어요.") }
        try FileManager.default.moveItem(at: download, to: zip)
        let size = (try FileManager.default.attributesOfItem(atPath: zip.path)[.size] as? NSNumber)?.intValue
        guard size == release.size, try Self.hash(zip) == release.hash else { throw RoomError("받은 업데이트 파일이 손상됐어요. 다시 시도해 주세요.") }
        guard let bundled = Bundle.main.url(forResource: "updater", withExtension: "sh") else { throw RoomError("업데이트 도우미를 찾지 못했어요.") }
        let script = work.appendingPathComponent("updater.sh")
        try FileManager.default.copyItem(at: bundled, to: script)
        // Validate and stage the bundle before saving the session or quitting.
        let stage = Process()
        stage.executableURL = URL(fileURLWithPath: "/bin/bash")
        stage.arguments = [script.path, "--prepare-update", zip.path, release.hash, Bundle.main.bundleURL.path, String(release.tag.dropFirst())]
        try stage.run()
        stage.waitUntilExit()
        guard stage.terminationStatus == 0 else { throw RoomError("앱을 설치할 폴더에 쓸 수 없거나 파일 검증에 실패했어요.") }
        return Prepared(script: script, zip: zip, hash: release.hash)
    }

    func finish(_ error: String) {
        installing = false
        status = "업데이트하지 못했어요. " + error
        changed?()
    }

    static func hash(_ url: URL) throws -> String {
        let stream = try FileHandle(forReadingFrom: url)
        defer { try? stream.close() }
        var hash = SHA256()
        while let data = try stream.read(upToCount: 65536), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func launch(_ prepared: Prepared) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [prepared.script.path, "--apply-update", prepared.zip.path, prepared.hash, Bundle.main.bundleURL.path,
                          String(ProcessInfo.processInfo.processIdentifier), errorURL.path]
        try task.run()
    }
}
