import Foundation

/// Coarse destination type. Drives formatting rules in the prompt.
public enum AppFamily: String, Codable, Sendable, CaseIterable {
    case email
    case workChat
    case personalChat
    case document
    case code
    case terminal
    case general

    // Bundle id prefixes. Keep this table small and obvious; users can
    // override per app later via settings.
    private static let table: [(prefix: String, family: AppFamily)] = [
        ("com.apple.mail", .email),
        ("com.microsoft.Outlook", .email),
        ("com.readdle.smartemail", .email),
        ("com.tinyspeck.slackmacgap", .workChat),
        ("com.microsoft.teams", .workChat),
        ("com.hnc.Discord", .workChat),
        ("com.mattermost.desktop", .workChat),
        ("com.apple.MobileSMS", .personalChat),
        ("net.whatsapp.WhatsApp", .personalChat),
        ("ru.keepcoder.Telegram", .personalChat),
        ("com.tencent.xinWeChat", .personalChat),
        ("jp.naver.line.mac", .personalChat),
        ("org.whispersystems.signal-desktop", .personalChat),
        ("com.apple.Notes", .document),
        ("notion.id", .document),
        ("md.obsidian", .document),
        ("com.apple.iWork.Pages", .document),
        ("com.microsoft.Word", .document),
        ("com.microsoft.VSCode", .code),
        ("com.todesktop.230313mzl4w4u92", .code), // Cursor
        ("com.exafunction.windsurf", .code),
        ("com.apple.dt.Xcode", .code),
        ("com.jetbrains.", .code),
        ("dev.zed.Zed", .code),
        ("com.sublimetext", .code),
        ("com.apple.Terminal", .terminal),
        ("com.googlecode.iterm2", .terminal),
        ("dev.warp.Warp", .terminal),
        ("com.mitchellh.ghostty", .terminal),
        ("net.kovidgoyal.kitty", .terminal),
    ]

    private static let urlTable: [(host: String, family: AppFamily)] = [
        ("mail.google.com", .email),
        ("outlook.live.com", .email),
        ("outlook.office.com", .email),
        ("app.slack.com", .workChat),
        ("teams.microsoft.com", .workChat),
        ("discord.com", .workChat),
        ("web.whatsapp.com", .personalChat),
        ("web.telegram.org", .personalChat),
        ("docs.google.com", .document),
        ("notion.so", .document),
        ("github.com", .code),
        ("gitlab.com", .code),
    ]

    public static func classify(_ ctx: AppContext) -> AppFamily {
        if let url = ctx.url, let host = URL(string: url)?.host?.lowercased() {
            for entry in urlTable where host == entry.host || host.hasSuffix("." + entry.host) {
                return entry.family
            }
        }
        if let bundle = ctx.bundleId {
            for entry in table where bundle.hasPrefix(entry.prefix) {
                return entry.family
            }
        }
        return .general
    }

    /// Rules appended to the system prompt. Presentation only; they never
    /// change the facts or the requested operation.
    public var styleRules: String {
        switch self {
        case .email:
            return "Destination: email. Produce an email body. Use a greeting only if the speaker addressed someone, short paragraphs, and a light closing if the content ends like a message. Never invent a subject line."
        case .workChat:
            return "Destination: work chat (Slack / Teams). Keep it short and conversational. Simple line breaks instead of headings. No greeting, no sign-off. No trailing period on a single-sentence message."
        case .personalChat:
            return "Destination: personal messaging. Keep the speaker's casual voice and short-message rhythm. Minimal punctuation, no headings, no sign-off."
        case .document:
            return "Destination: document or notes. Coherent paragraphs. Use bullet points or short headings only when the speech clearly has sections or multiple items."
        case .code:
            return "Destination: code editor or AI coding tool. Preserve identifiers, file paths, commands, versions, and error text exactly as spoken. Use compact bullets for goal / constraints / expected output when the speech implies them. Never write code that was not spoken."
        case .terminal:
            return "Destination: terminal or coding agent. Usually the speaker is writing a message or instruction, not a shell command; keep it as prose. Only when the speaker literally dictates a command, keep its flags and paths exactly. No markdown."
        case .general:
            return "Destination: unknown text field. Plain prose with normal punctuation. Use a list only when the speaker enumerated items."
        }
    }
}
