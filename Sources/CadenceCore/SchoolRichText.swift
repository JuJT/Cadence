import Foundation

/// PRONOTE publishes fragments of HTML, including entity-escaped fragments.
/// Convert them to readable text without loading a web view or remote resources.
public enum SchoolRichText {
    public static func plain(_ input: String) -> String {
        var text = input.replacingOccurrences(of: "\r\n", with: "\n")
        // Several servers wrap the HTML in an additional entity-encoded string.
        for _ in 0..<4 {
            let previous = text
            text = text.replacingOccurrences(of: "(?is)<!--.*?-->|<(script|style|iframe|object)\\b[^>]*>.*?</\\1\\s*>", with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: "(?i)<li\\b[^>]*>", with: "\n• ", options: .regularExpression)
            text = text.replacingOccurrences(of: "(?i)<br\\s*/?>|</(?:p|div|li|h[1-6]|tr|ul|ol)\\s*>", with: "\n", options: .regularExpression)
            text = text.replacingOccurrences(of: "(?i)</(?:td|th)\\s*>", with: " · ", options: .regularExpression)
            text = text.replacingOccurrences(of: "</?[A-Za-z][^>]*>", with: "", options: .regularExpression)
            text = decodeEntities(text)
            if text == previous { break }
        }
        return text.replacingOccurrences(of: "[ \\t\\u00a0]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " *\n *", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\n{2,}(?=• )", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeEntities(_ input: String) -> String {
        let entities: [String: String] = [
            "nbsp": " ", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "amp": "&",
            "eacute": "é", "egrave": "è", "ecirc": "ê", "euml": "ë", "agrave": "à", "acirc": "â",
            "ccedil": "ç", "icirc": "î", "iuml": "ï", "ocirc": "ô", "ouml": "ö", "ugrave": "ù",
            "ucirc": "û", "uuml": "ü", "Eacute": "É", "Agrave": "À", "Ccedil": "Ç",
            "ndash": "–", "mdash": "—", "hellip": "…", "laquo": "«", "raquo": "»",
            "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "bull": "•", "euro": "€",
            "times": "×", "divide": "÷", "le": "≤", "ge": "≥", "ne": "≠", "deg": "°"
        ]
        guard let regex = try? NSRegularExpression(pattern: "&(#(?:[xX][0-9A-Fa-f]+|[0-9]+)|[A-Za-z]+);") else { return input }
        var text = input
        for match in regex.matches(in: input, range: NSRange(input.startIndex..., in: input)).reversed() {
            guard let tokenRange = Range(match.range(at: 1), in: text), let range = Range(match.range, in: text) else { continue }
            let token = String(text[tokenRange])
            var replacement = entities[token]
            if token.hasPrefix("#") {
                let digits = String(token.dropFirst())
                let hex = digits.hasPrefix("x") || digits.hasPrefix("X")
                if let code = UInt32(hex ? String(digits.dropFirst()) : digits, radix: hex ? 16 : 10),
                   let scalar = UnicodeScalar(code), code != 0 {
                    replacement = String(scalar)
                }
            }
            if let replacement { text.replaceSubrange(range, with: replacement) }
        }
        return text
    }
}
