import Foundation

/// API host for the mobile field API (`/api/mobile/*`).
/// Production default is kapanservice.com; override in Account for local/staging.
enum AppConfig {
    static let productionBaseURL = URL(string: "https://kapanservice.com")!
    static let localDefaultURLString = "http://127.0.0.1:3000"

    private static let overrideKey = "kapan.mobile.apiBaseURL"

    /// Effective base URL (override if set, else production).
    static var baseURL: URL {
        if let raw = UserDefaults.standard.string(forKey: overrideKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let url = Self.normalizedURL(from: raw) {
            return url
        }
        return productionBaseURL
    }

    static var overrideString: String? {
        UserDefaults.standard.string(forKey: overrideKey)
    }

    static var isUsingOverride: Bool {
        guard let raw = overrideString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return false }
        return true
    }

    static var displayHost: String {
        baseURL.host ?? baseURL.absoluteString
    }

    /// Persist override (nil/empty → production). Returns false if the string is not a valid URL.
    @discardableResult
    static func setOverride(_ raw: String?) -> Bool {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: overrideKey)
            return true
        }
        guard normalizedURL(from: trimmed) != nil else { return false }
        UserDefaults.standard.set(trimmed, forKey: overrideKey)
        return true
    }

    static func resetToProduction() {
        UserDefaults.standard.removeObject(forKey: overrideKey)
    }

    private static func normalizedURL(from raw: String) -> URL? {
        var s = raw
        if !s.contains("://") {
            s = "https://\(s)"
        }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased(),
              (scheme == "https" || scheme == "http"),
              url.host != nil else {
            return nil
        }
        return url
    }
}
