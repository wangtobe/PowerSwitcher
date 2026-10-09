import Foundation

/// First preferred language wins. Chinese variants use Simplified Chinese; all others fall back to English.
enum L10n {
    static func chinese(preferred: [String], override: String? = nil) -> Bool {
        if override == "zh" { return true }
        if override == "en" { return false }
        return (preferred.first ?? "en").lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-").first == "zh"
    }
    // Cache for one application session so all open windows use a consistent language.
    static let isChinese = chinese(preferred: Locale.preferredLanguages,
                                    override: UserDefaults.standard.string(forKey: "interfaceLanguage"))
    static var locale: Locale { Locale(identifier: isChinese ? "zh_CN" : "en_US") }
}
func L(_ chinese: @autoclosure () -> String, _ english: @autoclosure () -> String) -> String {
    L10n.isChinese ? chinese() : english()
}
