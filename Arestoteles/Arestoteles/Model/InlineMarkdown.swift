import Foundation

/// The contract's `Text`: inline Markdown (**bold**, *italic*, `code`, links). Note links arrive as
/// `[shown text](arestoteles://note/<id>#<anchor>)`; a link to a missing note is plain text already; web links stay.
enum InlineMarkdown {
    /// For display: `AttributedString(markdown:)`, inline only, whitespace kept. Text that is not valid Markdown shows as
    /// it is.
    static func attributed(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace,
                                                              failurePolicy: .returnPartiallyParsedIfPossible)
        return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
    }

    /// The words without the Markdown: for search, Spotlight and prompts. A cheap scan rather than the full parser,
    /// because search indexes every block of every note.
    static func plain(_ markdown: String) -> String {
        var result = ""
        result.reserveCapacity(markdown.count)
        var index = markdown.startIndex
        while index < markdown.endIndex {
            let character = markdown[index]
            switch character {
            case "\\":
                // An escaped character stands for itself.
                let next = markdown.index(after: index)
                if next < markdown.endIndex {
                    result.append(markdown[next])
                    index = markdown.index(after: next)
                } else {
                    index = next
                }
            case "*", "_" where isEmphasis(markdown, at: index), "`":
                index = markdown.index(after: index)
            case "[":
                if let (text, end) = link(in: markdown, at: index) {
                    result += plain(text)
                    index = end
                } else {
                    result.append(character)
                    index = markdown.index(after: index)
                }
            default:
                result.append(character)
                index = markdown.index(after: index)
            }
        }
        return result
    }

    /// `[text](destination)` starting at `start`: the text and the index after the closing parenthesis.
    private static func link(in text: String, at start: String.Index) -> (String, String.Index)? {
        guard let close = text[start...].firstIndex(of: "]") else { return nil }
        let open = text.index(after: close)
        guard open < text.endIndex, text[open] == "(" else { return nil }
        var depth = 0
        var index = open
        while index < text.endIndex {
            switch text[index] {
            case "(": depth += 1
            case ")":
                depth -= 1
                if depth == 0 { return (String(text[text.index(after: start)..<close]), text.index(after: index)) }
            default: break
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// An underscore marks emphasis only at a word's edge ("snake_case" keeps its underscore).
    private static func isEmphasis(_ text: String, at index: String.Index) -> Bool {
        let before = index > text.startIndex ? text[text.index(before: index)] : " "
        let afterIndex = text.index(after: index)
        let after = afterIndex < text.endIndex ? text[afterIndex] : " "
        return !(before.isLetter || before.isNumber) || !(after.isLetter || after.isNumber)
    }
}
