import Foundation

/// Polls the GitHub Releases API for the latest published tag and, when it is
/// newer than the running build, exposes the release so the menu can surface a
/// "new version available" notice. Best-effort and silent on failure — a
/// missing network or rate-limited API just leaves `latest` nil.
@MainActor
final class UpdateChecker: ObservableObject {
    /// Set once a strictly-newer release is found; nil otherwise.
    @Published private(set) var available: Release?

    /// The version this build reports (CFBundleShortVersionString).
    let currentVersion: String

    private let latestReleaseURL = URL(
        string: "https://api.github.com/repos/lucianodiisouza/PoorDeck/releases/latest")!

    struct Release: Equatable {
        let version: String        // normalized, e.g. "0.2.0"
        let htmlURL: URL           // release page to open in the browser
    }

    init() {
        currentVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    /// Fires a check now. Safe to call repeatedly (e.g. each time the menu opens).
    func check() {
        Task { await checkAsync() }
    }

    private func checkAsync() async {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("PoorDeck", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String
        else { return }

        let latest = Self.normalize(tag)
        guard Self.isNewer(latest, than: currentVersion) else { return }

        let url = (json["html_url"] as? String).flatMap(URL.init)
            ?? URL(string: "https://github.com/lucianodiisouza/PoorDeck/releases/latest")!
        available = Release(version: latest, htmlURL: url)
    }

    /// Strips a leading "v" so `v0.2.0` and `0.2.0` compare equal.
    static func normalize(_ tag: String) -> String {
        var s = tag.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        return s
    }

    /// Numeric semver-style comparison ("0.10.0" > "0.9.0"), padding missing
    /// components with zeros. Non-numeric segments compare as 0.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = components(candidate), b = components(current)
        for i in 0..<max(a.count, b.count) {
            let l = i < a.count ? a[i] : 0
            let r = i < b.count ? b[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    private static func components(_ v: String) -> [Int] {
        v.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }
}
