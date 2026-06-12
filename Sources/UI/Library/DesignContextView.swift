import SwiftUI
import WebKit

struct DesignContextView: View {
    let context: BrowserDesignContext

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !context.fonts.isEmpty {
                section("Fonts") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(context.fonts.prefix(8)) { font in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(font.sampleText)
                                    .font(.custom(font.fontFamily, size: CGFloat(Double(font.fontSize.replacingOccurrences(of: "px", with: "")) ?? 15)))
                                    .lineLimit(1)
                                Text("\(font.fontFamily) · \(font.fontSize) · \(font.fontWeight) · \(font.count)x")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if !context.colors.isEmpty {
                section("Colors") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 8)], spacing: 8) {
                        ForEach(context.colors.prefix(16)) { color in
                            HStack(spacing: 7) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(cssColor: color.value))
                                    .frame(width: 22, height: 22)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(color.role).font(.caption2).foregroundStyle(.secondary)
                                    Text(color.value).font(.caption2).lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }

            if !context.cssTokens.isEmpty {
                section("CSS Tokens") {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(context.cssTokens.prefix(24)) { token in
                            HStack(alignment: .top, spacing: 8) {
                                Text(token.name)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 150, alignment: .leading)
                                Text(token.value)
                                    .font(.caption.monospaced())
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }

            if !context.buttons.isEmpty {
                section("Buttons") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                        ForEach(context.buttons.prefix(12)) { button in
                            VStack(alignment: .leading, spacing: 6) {
                                ButtonPreview(html: button.html)
                                    .frame(height: max(54, min(96, button.height + 26)))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                                Text(button.text)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
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
}

private struct ButtonPreview: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        let document = """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html,body{margin:0;width:100%;height:100%;background:transparent;overflow:hidden}
            body{display:flex;align-items:center;justify-content:center;padding:12px;box-sizing:border-box}
            *{max-width:100%;box-sizing:border-box}
          </style>
        </head>
        <body>\(html)</body>
        </html>
        """
        view.loadHTMLString(document, baseURL: nil)
    }
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
