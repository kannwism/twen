import AppKit
import TwenCore

/// Checks GitHub Releases for a newer version — once shortly after launch, then
/// every 24 hours. The result only ever surfaces as a menu item; there is no
/// nagging and no download. This is the app's single use of the network, and
/// Settings can turn it off entirely (SettingsStore.checkForUpdates).
@MainActor
final class UpdateChecker: ObservableObject {
    struct Update: Equatable {
        let version: String
        let url: URL
    }

    /// Non-nil once a check has seen a release newer than the running version.
    @Published private(set) var available: Update?

    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/kannwism/twen/releases/latest")!
    private static let checkInterval: TimeInterval = 24 * 60 * 60
    /// Launch check is deferred so it never competes with startup work.
    private static let launchDelay: TimeInterval = 10

    private let currentVersion: AppVersion?
    private var loopTask: Task<Void, Never>?

    init(currentVersionString: String? =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    ) {
        currentVersion = currentVersionString.flatMap(AppVersion.init)
    }

    /// Idempotent; a no-op when disabled in Settings or when the running copy has
    /// no version to compare against (bare `swift run` builds outside a bundle).
    func start() {
        guard SettingsStore.shared.checkForUpdates, loopTask == nil else { return }
        guard let currentVersion else {
            print("twen: no bundle version; update check disabled")
            return
        }
        loopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.launchDelay))
            while !Task.isCancelled {
                await self?.checkOnce(against: currentVersion)
                try? await Task.sleep(for: .seconds(Self.checkInterval))
            }
        }
    }

    /// One immediate, awaitable check — the --probe-update path.
    func checkNow() async {
        guard let currentVersion else { return }
        await checkOnce(against: currentVersion)
    }

    /// Probe hook (--probe-update): inject a result as if a check had found it.
    func surface(_ update: Update) {
        available = update
    }

    /// Stops future checks and drops an already-surfaced update from the menu.
    func stop() {
        loopTask?.cancel()
        loopTask = nil
        available = nil
    }

    private func checkOnce(against current: AppVersion) async {
        var request = URLRequest(url: Self.latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                print("twen: update check got HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return
            }
            struct Release: Decodable {
                let tag_name: String
                let html_url: URL
            }
            let release = try JSONDecoder().decode(Release.self, from: data)
            guard let latest = AppVersion(release.tag_name) else {
                print("twen: update check: unparseable tag \(release.tag_name)")
                return
            }
            if latest > current {
                print("twen: update available: \(current) -> \(latest)")
                available = Update(version: latest.description, url: release.html_url)
            } else if available != nil {
                // A yanked release can make "latest" older again; un-surface it.
                available = nil
            }
        } catch {
            // Offline is normal; stay quiet beyond the log and retry next cycle.
            print("twen: update check failed: \(error.localizedDescription)")
        }
    }
}
