import Foundation

/// Converts pasted HTML into Markdown. It handles the structure people paste most,
/// and falls back to plain text for everything else.
public enum HTMLToMarkdown {
    public static func convert(_ html: String) -> String {
        var text = html
        func replace(_ pattern: String, _ template: String) {
            text = text.replacingOccurrences(of: pattern, with: template, options: [.regularExpression, .caseInsensitive])
        }
        replace(#"<!--[\s\S]*?-->"#, "")
        replace(#"<(style|script|head|meta|title)\b[\s\S]*?(</\1>|$)"#, "")
        replace(#"<br\s*/?>"#, "\n")
        for level in 1...6 {
            let hashes = String(repeating: "#", count: level)
            replace("<h\(level)\\b[^>]*>([\\s\\S]*?)</h\(level)>", "\n\n\(hashes) $1\n\n")
        }
        replace(#"<(strong|b)\b[^>]*>([\s\S]*?)</\1>"#, "**$2**")
        replace(#"<(em|i)\b[^>]*>([\s\S]*?)</\1>"#, "*$2*")
        replace(#"<(del|s|strike)\b[^>]*>([\s\S]*?)</\1>"#, "~~$2~~")
        replace(#"<code\b[^>]*>([\s\S]*?)</code>"#, "`$1`")
        replace(#"<pre\b[^>]*>([\s\S]*?)</pre>"#, "\n\n```\n$1\n```\n\n")
        replace(#"<a\b[^>]*href="([^"]*)"[^>]*>([\s\S]*?)</a>"#, "[$2]($1)")
        replace(#"<img\b[^>]*src="([^"]*)"[^>]*/?>"#, "![]($1)")
        replace(#"<li\b[^>]*>([\s\S]*?)</li>"#, "- $1\n")
        replace(#"</?(ul|ol)\b[^>]*>"#, "\n")
        replace(#"<blockquote\b[^>]*>([\s\S]*?)</blockquote>"#, "\n\n> $1\n\n")
        replace(#"<hr\s*/?>"#, "\n\n---\n\n")
        replace(#"</(p|div|tr|table|section|article)>"#, "\n\n")
        replace(#"</t[dh]>"#, "  ")
        replace(#"<[^>]+>"#, "")
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'"]
        for (entity, value) in entities { text = text.replacingOccurrences(of: entity, with: value) }
        replace(#"[ \t]+\n"#, "\n")
        replace(#"\n{3,}"#, "\n\n")
        return jsTrim(text)
    }
}
