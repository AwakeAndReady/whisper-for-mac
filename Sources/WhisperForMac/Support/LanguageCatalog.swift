import Foundation

enum LanguageCatalog {
    static let supported: [(code: String, name: String)] = [
        ("auto", "Auto Detect"),
        ("en", "English"),
        ("de", "German"),
        ("fr", "French"),
        ("es", "Spanish"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("nl", "Dutch"),
        ("pl", "Polish"),
        ("cs", "Czech"),
        ("da", "Danish"),
        ("fi", "Finnish"),
        ("sv", "Swedish"),
        ("no", "Norwegian"),
        ("uk", "Ukrainian"),
        ("ru", "Russian"),
        ("tr", "Turkish"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("zh", "Chinese"),
    ]

    static func displayName(for code: String) -> String {
        supported.first(where: { $0.code == code })?.name ?? code
    }
}
