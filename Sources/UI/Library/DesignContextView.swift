import SwiftUI
import WebKit

struct DesignContextView: View {
    let context: BrowserDesignContext
    @State private var expandedFontFamilies: Set<String> = []
    @State private var cssTokensExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !context.fonts.isEmpty {
                section("Fonts") {
                    LazyVGrid(columns: fontColumns, alignment: .leading, spacing: 12) {
                        ForEach(groupedFonts.prefix(8)) { group in
                            FontFamilyCard(
                                group: group,
                                isExpanded: expandedFontFamilies.contains(group.id),
                                fontFaceCSS: context.fontFaceCSS,
                                toggle: {
                                    if expandedFontFamilies.contains(group.id) {
                                        expandedFontFamilies.remove(group.id)
                                    } else {
                                        expandedFontFamilies.insert(group.id)
                                    }
                                },
                                copy: copy
                            )
                        }
                    }
                }
            }

            if !context.colors.isEmpty {
                section("Colors") {
                    LazyVGrid(columns: colorColumns, spacing: 10) {
                        ForEach(context.colors.prefix(18)) { color in
                            ColorSwatchRow(color: color)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                copy(color.displayValue)
                            }
                            .help("Copy color")
                        }
                    }
                }
            }

            if !context.cssTokens.isEmpty {
                DisclosureGroup(isExpanded: $cssTokensExpanded) {
                    LazyVGrid(columns: cssColumns, alignment: .leading, spacing: 8) {
                        ForEach(context.cssTokens.prefix(80)) { token in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(token.name)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(token.value)
                                    .font(.caption.monospaced())
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.black.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                copy("\(token.name): \(token.value)")
                            }
                            .help("Copy CSS token")
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    HStack(spacing: 6) {
                        Text("CSS Tokens")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text("\(context.cssTokens.count)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.secondary)
            }

            if !context.buttons.isEmpty {
                section("Buttons") {
                    LazyVGrid(columns: buttonColumns, spacing: 12) {
                        ForEach(context.buttons.prefix(12)) { button in
                            VStack(alignment: .leading, spacing: 6) {
                                ButtonPreview(
                                    html: button.html,
                                    backgroundColor: button.backgroundColor,
                                    textColor: button.color
                                )
                                    .frame(height: max(86, min(120, button.height + 42)))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.12)))
                                    .overlay(
                                        Color.clear
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                copy(button.html)
                                            }
                                    )
                                    .help("Copy button HTML")
                                Text(button.text)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .onTapGesture {
                                        copy(button.text)
                                    }
                                    .help("Copy button text")
                            }
                        }
                    }
                }
            }
        }
    }

    private var groupedFonts: [FontFamilyGroup] {
        Dictionary(grouping: context.fonts) { normalizedFamily($0.fontFamily) }
            .map { key, fonts in
                FontFamilyGroup(
                    id: key,
                    displayName: fonts.first?.fontFamily.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? key,
                    fonts: fonts.sorted { lhs, rhs in
                        if lhs.count != rhs.count { return lhs.count > rhs.count }
                        return fontSizeValue(lhs.fontSize) > fontSizeValue(rhs.fontSize)
                    }
                )
            }
            .sorted { lhs, rhs in lhs.totalCount > rhs.totalCount }
    }

    private var fontColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 260, maximum: 420), spacing: 12)]
    }

    private var colorColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 150, maximum: 230), spacing: 10)]
    }

    private var cssColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 220, maximum: 360), spacing: 8)]
    }

    private var buttonColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 230, maximum: 360), spacing: 12)]
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

}

private struct FontFamilyGroup: Identifiable {
    let id: String
    let displayName: String
    let fonts: [BrowserDesignContext.FontInfo]

    var totalCount: Int { fonts.reduce(0) { $0 + $1.count } }
    var primaryFont: BrowserDesignContext.FontInfo { fonts[0] }
    var detailText: String {
        let sizes = Array(Set(fonts.map(\.fontSize))).sorted { fontSizeValue($0) < fontSizeValue($1) }
        let weights = Array(Set(fonts.map(\.fontWeight))).sorted()
        return "\(sizes.joined(separator: ", ")) · \(weights.joined(separator: "/")) · \(totalCount)x"
    }
}

private struct FontFamilyCard: View {
    let group: FontFamilyGroup
    let isExpanded: Bool
    let fontFaceCSS: String?
    let toggle: () -> Void
    let copy: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(group.displayName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Button(action: toggle) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Hide variants" : "Show variants")
            }

            FontPreview(font: group.primaryFont, fontFaceCSS: fontFaceCSS)
                .frame(height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 7))

            Text(group.detailText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if isExpanded {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(group.fonts.prefix(10)) { font in
                        HStack {
                            Text("\(font.fontSize) · \(font.fontWeight)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(font.count)x")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { copy(fontClipboardValue(font)) }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { copy(fontClipboardValue(group.primaryFont)) }
        .help("Copy font and Google Fonts link")
    }

    private func fontClipboardValue(_ font: BrowserDesignContext.FontInfo) -> String {
        let family = font.fontFamily.trimmingCharacters(in: .whitespacesAndNewlines)
        let googleFamily = family.replacingOccurrences(of: " ", with: "+")
        return "\(family)\nhttps://fonts.google.com/specimen/\(googleFamily)"
    }
}

private struct ColorSwatchRow: View {
    let color: BrowserDesignContext.ColorInfo

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Checkerboard()
                    .opacity(color.value.cssColorComponents?.alpha ?? 1 < 1 ? 0.55 : 0)
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(cssColor: color.value))
                RoundedRectangle(cornerRadius: 5)
                    .stroke(.white.opacity(0.16), lineWidth: 0.5)
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 2) {
                Text(color.role)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(color.displayValue)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(.black.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let tile: CGFloat = 6
            for x in stride(from: CGFloat(0), to: size.width, by: tile) {
                for y in stride(from: CGFloat(0), to: size.height, by: tile) {
                    let isDark = (Int(x / tile) + Int(y / tile)).isMultiple(of: 2)
                    context.fill(
                        Path(CGRect(x: x, y: y, width: tile, height: tile)),
                        with: .color(isDark ? .white.opacity(0.22) : .black.opacity(0.18))
                    )
                }
            }
        }
    }
}

private struct ButtonPreview: NSViewRepresentable {
    let html: String
    let backgroundColor: String?
    let textColor: String?

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let view = PassthroughScrollWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        let style = AdaptiveButtonStyle(backgroundColor: backgroundColor, textColor: textColor)
        let fallbackBackground = style.background
        let fallbackColor = style.text
        let document = """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html,body{margin:0;width:100%;height:100%;background:transparent;overflow:hidden}
            body{display:flex;align-items:center;justify-content:center;padding:12px;box-sizing:border-box}
            body>*{max-width:100%;min-width:min(78%,280px);min-height:38px;box-sizing:border-box;transform:none!important;animation:none!important;display:inline-flex!important;align-items:center!important;justify-content:center!important;text-align:center!important;overflow:hidden!important}
            button,a{vertical-align:middle;text-decoration:none;white-space:normal!important;overflow-wrap:anywhere!important}
            body>button,body>a,body>[role=button]{background:\(fallbackBackground)!important;color:\(fallbackColor)!important}
          </style>
        </head>
        <body>\(html)</body>
        </html>
        """
        view.loadHTMLString(document, baseURL: nil)
    }
}

private struct FontPreview: NSViewRepresentable {
    let font: BrowserDesignContext.FontInfo
    let fontFaceCSS: String?

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let view = PassthroughScrollWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        let family = font.fontFamily.htmlEscaped
        let sample = font.sampleText.htmlEscaped
        let size = font.fontSize.htmlEscaped
        let weight = font.fontWeight.htmlEscaped
        let css = (fontFaceCSS ?? "").styleBlockSafe
        let document = """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            \(css)
            html,body{margin:0;width:100%;height:100%;background:transparent;overflow:hidden;color-scheme:dark}
            body{display:flex;align-items:center;box-sizing:border-box;padding:4px 0}
            .sample{font-family:"\(family)", -apple-system, BlinkMacSystemFont, sans-serif;font-size:clamp(18px,\(size),56px);font-weight:\(weight);line-height:1.12;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden;color:rgba(255,255,255,.94);-webkit-font-smoothing:antialiased}
          </style>
        </head>
        <body><div class="sample">\(sample)</div></body>
        </html>
        """
        view.loadHTMLString(document, baseURL: nil)
    }
}

private final class PassthroughScrollWebView: WKWebView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}

private struct AdaptiveButtonStyle {
    let background: String
    let text: String

    init(backgroundColor: String?, textColor: String?) {
        let backgroundComponents = backgroundColor?.cssColorComponents
        let textComponents = textColor?.cssColorComponents
        let resolvedBackground = backgroundComponents?.alpha ?? 0 > 0.05 ? backgroundColor! : "rgba(255,255,255,.92)"
        let backgroundLuminance = backgroundComponents?.relativeLuminance ?? 0.92

        if let textColor,
           let textComponents,
           textComponents.alpha > 0.05,
           contrastRatio(textComponents.relativeLuminance, backgroundLuminance) >= 3.0 {
            self.text = textColor
        } else {
            self.text = backgroundLuminance > 0.45 ? "#151515" : "#ffffff"
        }
        self.background = resolvedBackground
    }
}

private struct CSSColorComponents {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    var relativeLuminance: Double {
        func linear(_ component: Double) -> Double {
            component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}

private func contrastRatio(_ lhs: Double, _ rhs: Double) -> Double {
    let lighter = max(lhs, rhs)
    let darker = min(lhs, rhs)
    return (lighter + 0.05) / (darker + 0.05)
}

private extension BrowserDesignContext.ColorInfo {
    var displayValue: String {
        value.cssHexOrOriginal
    }
}

private extension String {
    var htmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    var styleBlockSafe: String {
        replacingOccurrences(of: "</style", with: "<\\/style", options: [.caseInsensitive])
    }

    var cssHexOrOriginal: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let range = trimmed.range(of: #"rgba?\(([^\)]+)\)"#, options: .regularExpression) else {
            return self
        }
        let body = trimmed[range].drop { $0 != "(" }.dropFirst().dropLast()
        let parts = body.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count >= 3 else { return self }
        return "#" + parts.prefix(3)
            .map { String(format: "%02x", Int(max(0, min(255, $0)))) }
            .joined()
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var isTransparentCSS: Bool {
        let lower = trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.isEmpty || lower == "transparent" || lower == "rgba(0, 0, 0, 0)" || lower == "#00000000"
    }

    var cssColorComponents: CSSColorComponents? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed == "transparent" { return CSSColorComponents(red: 0, green: 0, blue: 0, alpha: 0) }
        if trimmed.hasPrefix("#") {
            let hex = String(trimmed.dropFirst())
            let expanded: String
            switch hex.count {
            case 3:
                expanded = hex.map { "\($0)\($0)" }.joined() + "ff"
            case 4:
                expanded = hex.map { "\($0)\($0)" }.joined()
            case 6:
                expanded = hex + "ff"
            case 8:
                expanded = hex
            default:
                return nil
            }
            guard let value = UInt64(expanded, radix: 16) else { return nil }
            return CSSColorComponents(
                red: Double((value >> 24) & 0xff) / 255,
                green: Double((value >> 16) & 0xff) / 255,
                blue: Double((value >> 8) & 0xff) / 255,
                alpha: Double(value & 0xff) / 255
            )
        }
        guard let range = trimmed.range(of: #"rgba?\(([^\)]+)\)"#, options: .regularExpression) else {
            return nil
        }
        let body = trimmed[range].drop { $0 != "(" }.dropFirst().dropLast()
        let parts = body.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count >= 3 else { return nil }
        return CSSColorComponents(
            red: max(0, min(255, parts[0])) / 255,
            green: max(0, min(255, parts[1])) / 255,
            blue: max(0, min(255, parts[2])) / 255,
            alpha: parts.count >= 4 ? max(0, min(1, parts[3])) : 1
        )
    }
}

private func normalizedFamily(_ family: String) -> String {
    family
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\"", with: "")
        .replacingOccurrences(of: "'", with: "")
        .lowercased()
}

private func fontSizeValue(_ size: String) -> Double {
    Double(size.replacingOccurrences(of: "px", with: "")) ?? 0
}

private extension Color {
    init(cssColor: String) {
        let trimmed = cssColor.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("#") {
            self.init(hex: String(trimmed.dropFirst()))
            return
        }
        guard let range = trimmed.range(of: #"rgba?\(([^\)]+)\)"#, options: .regularExpression) else {
            self = .secondary.opacity(0.25)
            return
        }
        let body = trimmed[range].drop { $0 != "(" }.dropFirst().dropLast()
        let parts = body.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count >= 3 else {
            self = .secondary.opacity(0.25)
            return
        }
        self = Color(
            red: parts[0] / 255,
            green: parts[1] / 255,
            blue: parts[2] / 255,
            opacity: parts.count >= 4 ? parts[3] : 1
        )
    }

    init(hex: String) {
        let expanded: String
        if hex.count == 3 {
            expanded = hex.map { "\($0)\($0)" }.joined()
        } else {
            expanded = hex
        }
        guard expanded.count == 6, let value = Int(expanded, radix: 16) else {
            self = .secondary.opacity(0.25)
            return
        }
        self = Color(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }
}
