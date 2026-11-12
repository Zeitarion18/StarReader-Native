import Foundation

/// Generates a standards-based, self-contained WordprocessingML package from
/// the CURRENT StarReader library, not the originally imported DOCX.
/// The XML conversion has no UIKit dependencies and is tested separately.
enum DocxWordprocessingML {
    enum Error: LocalizedError {
        case noChapters
        case emptyDocument
        case oversized
        case invalidTitle

        var errorDescription: String? {
            switch self {
            case .noChapters: return "В выбранном томе пока нет глав для экспорта."
            case .emptyDocument: return "В выбранной главе нет текста."
            case .oversized: return "Документ слишком большой для безопасного экспорта в Word."
            case .invalidTitle: return "Не удалось определить название документа."
            }
        }
    }

    struct Part {
        let path: String
        let bytes: Data
    }

    private static let xmlHeader = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#
    private static let mainNamespace =
        "http://schemas.openxmlformats.org/wordprocessingml/2006/main"

    static func filename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
            .union(.controlCharacters)
        let safe = String(String.UnicodeScalarView(
            value.unicodeScalars.map { invalid.contains($0) ? "_" : $0 }
        ))
        let normalized = safe.replacingOccurrences(
            of: #"\s+"#, with: " ", options: .regularExpression
        ).trimmingCharacters(in: CharacterSet(
            charactersIn: " ._"
        ).union(.whitespacesAndNewlines))
        return String((normalized.isEmpty ? "StarReader" : normalized).prefix(105)) + ".docx"
    }

    /// A package with no private author metadata and with standard .docx
    /// relationships; it can be opened by Word, Pages and LibreOffice.
    static func package(
        chapters: [LibraryChapter],
        volumeTitle: String? = nil,
        workTitle: String? = nil,
        created: Date = Date()
    ) throws -> [Part] {
        guard !chapters.isEmpty else { throw Error.noChapters }
        guard chapters.count <= 500 else { throw Error.oversized }
        guard chapters.contains(where: {
            $0.paragraphs.contains {
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }) else {
            throw Error.emptyDocument
        }
        let amount = chapters.reduce(0) { partial, chapter in
            partial + chapter.totalCharacters
        }
        let paragraphCount = chapters.reduce(0) { $0 + $1.paragraphs.count }
        // The same strict limits are enforced by StarReader's existing
        // import parser, which verifies every resulting exported DOCX.
        guard amount <= 7_500_000, paragraphCount <= 34_000 else {
            throw Error.oversized
        }

        let title = volumeTitle ?? chapters[0].displayTitle
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Error.invalidTitle
        }

        let wordXML = documentXML(
            title: title,
            workTitle: workTitle,
            chapters: chapters,
            isVolume: volumeTitle != nil
        )
        let formattedDate = ISO8601DateFormatter().string(from: created)
        let core = xmlHeader + """
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <dc:title>\(escape(title))</dc:title>
          <dc:creator>StarReader</dc:creator>
          <cp:lastModifiedBy>StarReader</cp:lastModifiedBy>
          <dcterms:created xsi:type="dcterms:W3CDTF">\(formattedDate)</dcterms:created>
          <dcterms:modified xsi:type="dcterms:W3CDTF">\(formattedDate)</dcterms:modified>
        </cp:coreProperties>
        """

        let files: [(String, String)] = [
            ("[Content_Types].xml", xmlHeader + """
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
              <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
              <Default Extension="xml" ContentType="application/xml"/>
              <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
              <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
              <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
              <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
            </Types>
            """),
            ("_rels/.rels", xmlHeader + """
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
              <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
              <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
            </Relationships>
            """),
            ("word/_rels/document.xml.rels", xmlHeader + """
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
            </Relationships>
            """),
            ("word/document.xml", wordXML),
            ("word/styles.xml", stylesXML),
            ("docProps/core.xml", core),
            ("docProps/app.xml", xmlHeader + """
            <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
              <Application>StarReader</Application>
            </Properties>
            """)
        ]
        let parts = files.map { Part(path: $0.0, bytes: Data($0.1.utf8)) }
        guard parts.reduce(0, { $0 + $1.bytes.count }) <= 50 * 1024 * 1024 else {
            throw Error.oversized
        }
        return parts
    }

    private static func documentXML(
        title: String,
        workTitle: String?,
        chapters: [LibraryChapter],
        isVolume: Bool
    ) -> String {
        var body = ""
        body += paragraph(title, style: "Title", pageBreakBefore: false)
        if let workTitle, !workTitle.isEmpty {
            body += paragraph(workTitle, style: "Subtitle", pageBreakBefore: false)
        }

        for (index, chapter) in chapters.enumerated() {
            if isVolume {
                body += paragraph(
                    chapter.displayTitle,
                    style: "Heading1",
                    pageBreakBefore: index > 0
                )
            }
            for source in chapter.paragraphs {
                // Never rewrite or trim a library paragraph on export.
                body += paragraph(
                    source.text,
                    style: source.heading ? "Heading2" : "Normal",
                    pageBreakBefore: false
                )
            }
        }
        body += """
        <w:sectPr>
          <w:pgSz w:w="11906" w:h="16838"/>
          <w:pgMar w:top="1275" w:right="1300" w:bottom="1275" w:left="1500" w:header="700" w:footer="700" w:gutter="0"/>
        </w:sectPr>
        """
        return xmlHeader + "<w:document xmlns:w=\"" + mainNamespace +
            "\"><w:body>" + body + "</w:body></w:document>"
    }

    private static func paragraph(
        _ source: String,
        style: String,
        pageBreakBefore: Bool
    ) -> String {
        let pageBreak = pageBreakBefore ? "<w:pageBreakBefore/>" : ""
        var result = "<w:p><w:pPr><w:pStyle w:val=\"" + style + "\"/>" +
            pageBreak + "</w:pPr><w:r>"
        // w:t always uses xml:space=preserve, so leading/trailing whitespace,
        // including spaces around tabs and line breaks, is retained.
        var textBuffer = ""
        func flush() {
            if !textBuffer.isEmpty {
                result += "<w:t xml:space=\"preserve\">" +
                    escape(textBuffer) + "</w:t>"
                textBuffer = ""
            }
        }
        for scalar in source.unicodeScalars {
            switch scalar.value {
            case 0x09:
                flush()
                result += "<w:tab/>"
            case 0x0A, 0x0D:
                flush()
                result += "<w:br/>"
            default:
                if allowedXMLScalar(scalar) { textBuffer.unicodeScalars.append(scalar) }
            }
        }
        flush()
        result += "</w:r></w:p>"
        return result
    }

    private static func allowedXMLScalar(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        return v == 0x09 || v == 0x0A || v == 0x0D ||
            (v >= 0x20 && v <= 0xD7FF) ||
            (v >= 0xE000 && v <= 0xFFFD) ||
            (v >= 0x10000 && v <= 0x10FFFF)
    }

    private static func escape(_ source: String) -> String {
        var xml = ""
        xml.reserveCapacity(source.utf8.count)
        for scalar in source.unicodeScalars {
            guard allowedXMLScalar(scalar) else { continue }
            switch scalar.value {
            case 0x26: xml += "&amp;"
            case 0x3C: xml += "&lt;"
            case 0x3E: xml += "&gt;"
            case 0x22: xml += "&quot;"
            case 0x27: xml += "&apos;"
            default: xml.unicodeScalars.append(scalar)
            }
        }
        return xml
    }

    private static let stylesXML = xmlHeader + """
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:docDefaults>
        <w:rPrDefault><w:rPr><w:rFonts w:ascii="Georgia" w:hAnsi="Georgia" w:cs="Georgia"/><w:sz w:val="24"/><w:lang w:val="ru-RU"/></w:rPr></w:rPrDefault>
        <w:pPrDefault><w:pPr><w:spacing w:after="140" w:line="310" w:lineRule="auto"/></w:pPr></w:pPrDefault>
      </w:docDefaults>
      <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
        <w:name w:val="Normal"/>
        <w:pPr><w:spacing w:after="140" w:line="310" w:lineRule="auto"/><w:ind w:firstLine="425"/><w:jc w:val="both"/></w:pPr>
      </w:style>
      <w:style w:type="paragraph" w:styleId="Title">
        <w:name w:val="Title"/>
        <w:basedOn w:val="Normal"/>
        <w:pPr><w:spacing w:before="260" w:after="360"/><w:jc w:val="center"/></w:pPr>
        <w:rPr><w:b/><w:sz w:val="38"/></w:rPr>
      </w:style>
      <w:style w:type="paragraph" w:styleId="Subtitle">
        <w:name w:val="Subtitle"/>
        <w:basedOn w:val="Normal"/>
        <w:pPr><w:spacing w:after="260"/><w:jc w:val="center"/></w:pPr>
        <w:rPr><w:i/><w:sz w:val="22"/></w:rPr>
      </w:style>
      <w:style w:type="paragraph" w:styleId="Heading1">
        <w:name w:val="heading 1"/>
        <w:basedOn w:val="Normal"/>
        <w:next w:val="Normal"/>
        <w:pPr><w:keepNext/><w:spacing w:before="280" w:after="220"/><w:jc w:val="center"/></w:pPr>
        <w:rPr><w:b/><w:sz w:val="30"/></w:rPr>
      </w:style>
      <w:style w:type="paragraph" w:styleId="Heading2">
        <w:name w:val="heading 2"/>
        <w:basedOn w:val="Normal"/>
        <w:next w:val="Normal"/>
        <w:pPr><w:keepNext/><w:spacing w:before="190" w:after="160"/></w:pPr>
        <w:rPr><w:b/><w:sz w:val="26"/></w:rPr>
      </w:style>
    </w:styles>
    """
}
