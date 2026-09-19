import Foundation
import XCTest

/// `Sources` と `Tests` の DocC が、CONTRIBUTING.md の書式どおりかを確かめる。
///
/// 見るのは機械的に判定できる書式だけ。要約の書き出しや、コードを言い換えただけの
/// コメントは判定できないので、レビューで見る。
final class DocumentationStyleTests: XCTestCase {

    /// `Sources` の DocC が書式どおりであることを確かめる。
    func testSourcesFollowDocumentationStyle() throws {
        let findings = try DocumentationAudit.findings(
            in: repositoryRoot().appendingPathComponent("Sources"),
            rules: DocumentationAudit.Rules(requiresPublicDocumentation: true)
        )
        XCTAssertEqual(findings, [], report(findings))
    }

    /// テストに public な API はないため、`Tests` では書式だけを見る。
    func testTestsFollowDocumentationStyle() throws {
        let findings = try DocumentationAudit.findings(
            in: repositoryRoot().appendingPathComponent("Tests"),
            rules: DocumentationAudit.Rules(requiresPublicDocumentation: false)
        )
        XCTAssertEqual(findings, [], report(findings))
    }

    /// 検査が実際に違反を捕まえることを確かめる。
    ///
    /// これがないと、判定が壊れて何も見ていない状態になっても両方のテストが通る。
    func testAuditDetectsViolations() {
        let rules = DocumentationAudit.Rules(requiresPublicDocumentation: true)

        assertDetects(
            .missingDocumentation,
            in: """
            public struct Sample {
                public var value: Int
            }
            """,
            rules: rules
        )

        assertDetects(
            .missingDocumentation,
            in: """
            /// 見本。
            public enum Sample {
                case first
            }
            """,
            rules: rules
        )

        assertDetects(
            .singularParameter,
            in: """
            /// 見本。
            public struct Sample {
                /// 値を足す。
                ///
                /// - Parameter value: 足す値。
                /// - Returns: 足した結果。
                public func adding(_ value: Int) -> Int { value }
            }
            """,
            rules: rules
        )

        assertDetects(
            .undocumentedParameter,
            in: """
            /// 見本。
            public struct Sample {
                /// 値を足す。
                ///
                /// - Parameters:
                ///   - value: 足す値。
                /// - Returns: 足した結果。
                public func adding(_ value: Int, twice: Bool) -> Int { value }
            }
            """,
            rules: rules
        )

        assertDetects(
            .unknownParameter,
            in: """
            /// 見本。
            public struct Sample {
                /// 値を足す。
                ///
                /// - Parameters:
                ///   - amount: 足す値。
                /// - Returns: 足した結果。
                public func adding(_ value: Int) -> Int { value }
            }
            """,
            rules: rules
        )

        assertDetects(
            .parameterOrder,
            in: """
            /// 見本。
            public struct Sample {
                /// 値を足す。
                ///
                /// - Parameters:
                ///   - twice: 二度足すか。
                ///   - value: 足す値。
                /// - Returns: 足した結果。
                public func adding(_ value: Int, twice: Bool) -> Int { value }
            }
            """,
            rules: rules
        )

        assertDetects(
            .missingReturns,
            in: """
            /// 見本。
            public struct Sample {
                /// 値を返す。
                public func value() -> Int { 0 }
            }
            """,
            rules: rules
        )

        assertDetects(
            .missingThrows,
            in: """
            /// 見本。
            public struct Sample {
                /// 何かする。
                public func act() throws {}
            }
            """,
            rules: rules
        )

        assertDetects(
            .commentBetweenDocumentationAndDeclaration,
            in: """
            /// 見本。
            public struct Sample {
                /// 値。
                // 割り込みコメント。
                public var value: Int
            }
            """,
            rules: rules
        )
    }

    // MARK: - 補助

    /// リポジトリの最上位。
    ///
    /// - Returns: このファイルから数えた 3 つ上のディレクトリ。
    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// 失敗時に出す、違反を並べた文。
    ///
    /// - Parameters:
    ///   - findings: 見つかった違反。
    /// - Returns: 1 行に 1 件並べた文。違反がなければ空文字列。
    private func report(_ findings: [DocumentationAudit.Finding]) -> String {
        guard !findings.isEmpty else { return "" }
        return "CONTRIBUTING.md の書式に合っていない箇所がある:\n"
            + findings.map { "  \($0)" }.joined(separator: "\n")
    }

    /// 見本のソースから、狙った種類の違反が見つかることを確かめる。
    ///
    /// - Parameters:
    ///   - kind: 見つかるべき違反の種類。
    ///   - source: 違反を含む見本のソース。
    ///   - rules: 適用する規則。
    ///   - file: 失敗を報告する位置のファイル。
    ///   - line: 失敗を報告する位置の行。
    private func assertDetects(
        _ kind: DocumentationAudit.Finding.Kind,
        in source: String,
        rules: DocumentationAudit.Rules,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let findings = DocumentationAudit.findings(in: source, path: "見本.swift", rules: rules)
        XCTAssertTrue(
            findings.contains(where: { $0.kind == kind }),
            "\(kind) を検知できていない。検知したのは \(findings)",
            file: file,
            line: line
        )
    }
}

/// Swift のソースを行単位で読み、DocC の書式の違反を集める。
enum DocumentationAudit {

    /// 違反 1 件。
    struct Finding: Equatable, CustomStringConvertible {

        /// 違反の種類。
        enum Kind: Equatable {
            /// public な宣言に DocC がない。
            case missingDocumentation
            /// 単数形の `- Parameter x:` を使っている。
            case singularParameter
            /// 説明のない引数がある。
            case undocumentedParameter
            /// 宣言にない引数の説明がある。
            case unknownParameter
            /// 引数の説明の順序が宣言と違う。
            case parameterOrder
            /// 返り値があるのに `- Returns:` がない。
            case missingReturns
            /// エラーを投げるのに `- Throws:` がない。
            case missingThrows
            /// DocC と宣言の間に `//` が挟まっている。
            case commentBetweenDocumentationAndDeclaration
        }

        /// 違反の種類。
        let kind: Kind
        /// 違反のあるファイル。
        let path: String
        /// 違反のある行。1 起点。
        let line: Int
        /// 何が問題かを述べた文。
        let detail: String

        var description: String { "\(path):\(line) \(detail)" }
    }

    /// 適用する規則。
    struct Rules {
        /// public な宣言に、DocC と引数・返り値・エラーの記載を求める。
        var requiresPublicDocumentation: Bool
    }

    /// ディレクトリの下にあるすべての Swift ファイルを調べる。
    ///
    /// - Parameters:
    ///   - directory: 調べるディレクトリ。
    ///   - rules: 適用する規則。
    /// - Returns: 見つかった違反。パスと行の順に並ぶ。
    /// - Throws: ディレクトリをたどれなければ `CocoaError`。
    static func findings(in directory: URL, rules: Rules) throws -> [Finding] {
        let manager = FileManager.default
        guard let walker = manager.enumerator(atPath: directory.path) else {
            return []
        }

        var results: [Finding] = []
        for case let relative as String in walker where relative.hasSuffix(".swift") {
            // この検査自身は読み飛ばす。見本として置いた違反が本物の宣言として数えられる。
            if relative.hasSuffix("DocumentationStyleTests.swift") { continue }

            let url = directory.appendingPathComponent(relative)
            let contents = try String(contentsOf: url, encoding: .utf8)
            let name = directory.lastPathComponent + "/" + relative
            results.append(contentsOf: findings(in: contents, path: name, rules: rules))
        }
        return results
    }

    /// ソース 1 つ分の文字列を調べる。
    ///
    /// - Parameters:
    ///   - contents: Swift のソース。
    ///   - path: 違反の報告に使うファイル名。
    ///   - rules: 適用する規則。
    /// - Returns: 見つかった違反。行の順に並ぶ。
    static func findings(in contents: String, path: String, rules: Rules) -> [Finding] {
        let lines = contents.components(separatedBy: "\n")
        var results: [Finding] = []

        var depth = 0
        var scopes: [Scope] = []

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let code = strippingLiteralsAndComments(line)

            if let found = declaration(in: trimmed) {
                let enclosing = scopes.last
                let isAtMemberLevel = enclosing?.memberDepth == depth
                let isTypeDeclaration = typeKeywords.contains(found.keyword)

                // 関数の中の `let` や `switch` の `case` は宣言として数えない。
                var isCountedDeclaration = isTypeDeclaration || isAtMemberLevel
                if found.keyword == "case" && enclosing?.keyword != "enum" {
                    isCountedDeclaration = false
                }

                if isCountedDeclaration {
                    let isPublic = found.keyword == "case"
                        ? (enclosing?.isPublic ?? false)
                        : found.isPublic
                    results.append(
                        contentsOf: findings(
                            forDeclarationAt: index,
                            keyword: found.keyword,
                            isPublic: isPublic,
                            in: lines,
                            path: path,
                            rules: rules
                        )
                    )
                }

                if isTypeDeclaration {
                    scopes.append(
                        Scope(keyword: found.keyword, memberDepth: depth + 1, isPublic: found.isPublic)
                    )
                }
            }

            depth += code.filter { $0 == "{" }.count - code.filter { $0 == "}" }.count
            while let last = scopes.last, depth < last.memberDepth {
                scopes.removeLast()
            }
        }
        return results
    }

    // MARK: - 宣言 1 つ分の判定

    /// 型の内側を表す。
    private struct Scope {
        /// 型の種類を表すキーワード。
        let keyword: String
        /// メンバーが並ぶ波括弧の深さ。
        let memberDepth: Int
        /// public な型か。
        let isPublic: Bool
    }

    private static let typeKeywords: Set<String> = ["enum", "struct", "class", "protocol", "actor", "extension"]

    private static let memberKeywords: Set<String> = [
        "func", "init", "var", "let", "subscript", "case", "associatedtype", "typealias",
    ]

    private static let modifiers: Set<String> = [
        "public", "open", "private", "internal", "fileprivate", "static", "final", "mutating",
        "nonmutating", "override", "required", "convenience", "indirect", "weak", "unowned",
        "lazy", "dynamic", "class",
    ]

    /// [swift/docs/DocumentationComments.md](https://github.com/apple/swift/blob/main/docs/DocumentationComments.md)
    /// にあるコールアウト。
    private static let calloutNames: Set<String> = [
        "Attention", "Author", "Authors", "Bug", "Complexity", "Copyright", "Date", "Experiment",
        "Important", "Invariant", "Note", "Parameter", "Parameters", "Postcondition",
        "Precondition", "Remark", "Remarks", "Requires", "Returns", "See", "Since", "Throws",
        "Todo", "Version", "Warning",
    ]

    /// 宣言 1 つ分を調べる。
    ///
    /// - Parameters:
    ///   - index: 宣言のある行。
    ///   - keyword: 宣言のキーワード。
    ///   - isPublic: public な宣言か。
    ///   - lines: ソースの全行。
    ///   - path: 違反の報告に使うファイル名。
    ///   - rules: 適用する規則。
    /// - Returns: この宣言に見つかった違反。
    private static func findings(
        forDeclarationAt index: Int,
        keyword: String,
        isPublic: Bool,
        in lines: [String],
        path: String,
        rules: Rules
    ) -> [Finding] {
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        let summary = String(trimmed.prefix(60))
        let comments = documentation(above: index, in: lines)
        var results: [Finding] = []

        func add(_ kind: Finding.Kind, _ detail: String) {
            results.append(Finding(kind: kind, path: path, line: index + 1, detail: detail))
        }

        if comments.hasInterleavedComment {
            add(.commentBetweenDocumentationAndDeclaration, "DocC と宣言の間に `//` がある: \(summary)")
        }
        if comments.lines.contains(where: { $0.hasPrefix("- Parameter ") }) {
            add(.singularParameter, "単数形の `- Parameter` を使っている: \(summary)")
        }
        if rules.requiresPublicDocumentation && isPublic && comments.lines.isEmpty {
            add(.missingDocumentation, "public な宣言に DocC がない: \(summary)")
        }

        guard keyword == "func" || keyword == "init" || keyword == "subscript",
              let parsed = signature(at: index, in: lines)
        else {
            return results
        }

        let declared = parsed.names.filter { $0 != "_" }
        let documented = documentedParameters(in: comments.lines)

        if !comments.lines.isEmpty {
            let unknown = documented.filter { !declared.contains($0) }
            if !unknown.isEmpty {
                add(.unknownParameter, "宣言にない引数の説明がある: \(unknown)")
            }
            if documented.filter({ declared.contains($0) }) != declared.filter({ documented.contains($0) }) {
                add(.parameterOrder, "引数の説明の順序が宣言と違う: \(declared) に対して \(documented)")
            }
        }

        guard rules.requiresPublicDocumentation, isPublic, !comments.lines.isEmpty else {
            return results
        }

        let missing = declared.filter { !documented.contains($0) }
        if !missing.isEmpty {
            add(.undocumentedParameter, "説明のない引数がある: \(missing)")
        }
        if parsed.suffix.contains("throws") && !comments.lines.contains(where: { $0.hasPrefix("- Throws:") }) {
            add(.missingThrows, "エラーを投げるのに `- Throws:` がない: \(summary)")
        }
        // subscript は何にアクセスするかを要約で述べる。`- Returns:` は求めない。
        if keyword == "func",
           parsed.suffix.contains("->"),
           !returnsVoid(parsed.suffix),
           !comments.lines.contains(where: { $0.hasPrefix("- Returns:") }) {
            add(.missingReturns, "返り値があるのに `- Returns:` がない: \(summary)")
        }
        return results
    }

    // MARK: - 文字列の読み取り

    /// 行から宣言のキーワードと公開範囲を読む。
    ///
    /// - Parameters:
    ///   - trimmed: 前後の空白を落とした 1 行。
    /// - Returns: 宣言ならキーワードと public かどうか。宣言でなければ `nil`。
    private static func declaration(in trimmed: String) -> (keyword: String, isPublic: Bool)? {
        guard !trimmed.isEmpty, !trimmed.hasPrefix("//") else { return nil }

        let words = trimmed
            .replacingOccurrences(of: "(", with: " (")
            .split(separator: " ")
            .map { String($0) }

        var isPublic = false
        for word in words {
            // `private(set)` を分けた後ろ半分のような、修飾子の続きは読み飛ばす。
            if word.hasPrefix("(") { continue }
            let base = word.split(separator: "(").first.map { String($0) } ?? word
            if base == "public" || base == "open" {
                isPublic = true
                continue
            }
            if word.hasPrefix("@") || word.hasPrefix("`") {
                continue
            }
            if typeKeywords.contains(base) {
                return (base, isPublic)
            }
            if memberKeywords.contains(base) {
                return (base, isPublic)
            }
            if modifiers.contains(base) {
                continue
            }
            return nil
        }
        return nil
    }

    /// 宣言の直前にある注釈を読む。
    ///
    /// - Parameters:
    ///   - index: 宣言のある行。
    ///   - lines: ソースの全行。
    /// - Returns: DocC の各行（`///` を除く）と、DocC より後ろに `//` が挟まっているか。
    private static func documentation(
        above index: Int,
        in lines: [String]
    ) -> (lines: [String], hasInterleavedComment: Bool) {
        var run: [String] = []
        var cursor = index - 1
        while cursor >= 0 {
            let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("//") || trimmed.hasPrefix("@") else { break }
            run.insert(trimmed, at: 0)
            cursor -= 1
        }

        var docLines: [String] = []
        var hasInterleavedComment = false
        for entry in run {
            if entry.hasPrefix("///") {
                docLines.append(String(entry.dropFirst(3)).trimmingCharacters(in: .whitespaces))
            } else if entry.hasPrefix("//") && !docLines.isEmpty {
                // DocC と宣言の間に `//` があると、DocC は宣言に結び付かない。
                hasInterleavedComment = true
                docLines = []
            }
        }
        return (docLines, hasInterleavedComment)
    }

    /// DocC の `- Parameters:` に並ぶ引数名を読む。
    ///
    /// - Parameters:
    ///   - documentation: DocC の各行。
    /// - Returns: 並んでいる順の引数名。
    private static func documentedParameters(in documentation: [String]) -> [String] {
        var names: [String] = []
        var isInsideParameters = false
        for entry in documentation {
            guard entry.hasPrefix("- "), let colon = entry.firstIndex(of: ":") else { continue }
            let label = String(entry[entry.index(entry.startIndex, offsetBy: 2)..<colon])
            if calloutNames.contains(label) {
                isInsideParameters = (label == "Parameters")
                continue
            }
            if isInsideParameters {
                names.append(label)
            }
        }
        return names
    }

    /// 宣言のシグネチャから、DocC が参照する引数名と、引数リストより後ろを読む。
    ///
    /// - Parameters:
    ///   - index: 宣言の始まる行。
    ///   - lines: ソースの全行。
    /// - Returns: 引数名と、閉じ括弧より後ろの文字列。括弧が見つからなければ `nil`。
    private static func signature(at index: Int, in lines: [String]) -> (names: [String], suffix: String)? {
        var text = ""
        var depth = 0
        var hasOpened = false
        var cursor = index
        while cursor < lines.count {
            let code = strippingLiteralsAndComments(lines[cursor])
            text += code + " "
            for character in code {
                if character == "(" {
                    depth += 1
                    hasOpened = true
                } else if character == ")" {
                    depth -= 1
                }
            }
            if hasOpened && depth <= 0 { break }
            cursor += 1
        }

        guard let open = text.firstIndex(of: "(") else { return nil }
        let body = Array(text[text.index(after: open)...])

        var level = 1
        var end = body.count
        for (offset, character) in body.enumerated() {
            if character == "(" {
                level += 1
            } else if character == ")" {
                level -= 1
                if level == 0 {
                    end = offset
                    break
                }
            }
        }

        let suffix = end + 1 <= body.count ? String(body[(end + 1)...]) : ""
        var names: [String] = []
        for part in splitAtTopLevel(Array(body[0..<end]), separator: ",") {
            var head = ""
            var nesting = 0
            var previous: Character = " "
            for character in part {
                if character == "(" || character == "[" || character == "<" {
                    nesting += 1
                } else if character == ")" || character == "]" || (character == ">" && previous != "-") {
                    nesting -= 1
                }
                if character == ":" && nesting == 0 { break }
                head.append(character)
                previous = character
            }
            let tokens = head
                .split(separator: " ")
                .map { String($0) }
                .filter { !$0.hasPrefix("@") && $0 != "inout" }
            if let name = tokens.last {
                names.append(name)
            }
        }
        return (names, suffix)
    }

    /// 括弧の外にある区切り文字で分ける。
    ///
    /// - Parameters:
    ///   - characters: 分ける文字列。
    ///   - separator: 区切り文字。
    /// - Returns: 分けた各部分。空白だけの部分は含まない。
    private static func splitAtTopLevel(_ characters: [Character], separator: Character) -> [String] {
        var parts: [String] = []
        var current = ""
        var nesting = 0
        var previous: Character = " "
        for character in characters {
            if character == "(" || character == "[" || character == "<" {
                nesting += 1
            } else if character == ")" || character == "]" || (character == ">" && previous != "-") {
                nesting -= 1
            }
            if character == separator && nesting == 0 {
                parts.append(current)
                current = ""
            } else {
                current.append(character)
            }
            previous = character
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append(current)
        }
        return parts
    }

    /// 返り値が `Void` かを調べる。
    ///
    /// - Parameters:
    ///   - suffix: 引数リストより後ろの文字列。
    /// - Returns: 返り値が `Void` または `()` なら `true`。
    private static func returnsVoid(_ suffix: String) -> Bool {
        guard let arrow = suffix.range(of: "->") else { return false }
        let tail = suffix[arrow.upperBound...]
            .split(separator: "{").first.map { String($0) } ?? ""
        let type = tail.trimmingCharacters(in: .whitespaces)
        return type == "Void" || type == "()"
    }

    /// 行から文字列リテラルと `//` 以降を取り除く。
    ///
    /// - Parameters:
    ///   - line: ソースの 1 行。
    /// - Returns: 波括弧を数えるための、コードだけが残った文字列。
    private static func strippingLiteralsAndComments(_ line: String) -> String {
        var result = ""
        var isInString = false
        var isEscaped = false
        var previous: Character = " "
        for character in line {
            if isInString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInString = false
                }
                continue
            }
            if character == "\"" {
                isInString = true
                continue
            }
            if character == "/" && previous == "/" {
                result.removeLast()
                break
            }
            result.append(character)
            previous = character
        }
        return result
    }
}
