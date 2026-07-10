import PhosphorSwift
import SwiftUI

struct TagSymbolView: View {
    let symbol: TagSymbol?
    var size: CGFloat = 14

    var body: some View {
        if let symbol {
            switch symbol.kind {
            case .emoji:
                Text(symbol.value.isEmpty ? TagSymbol.fallbackEmoji : symbol.value)
                    .font(.system(size: size))
                    .frame(width: size + 4, height: size + 4)
            case .phosphor:
                phosphorIcon(symbol.value)
                    .frame(width: size, height: size)
            }
        }
    }

    @ViewBuilder
    private func phosphorIcon(_ value: String) -> some View {
        switch PhosphorTagIcon(rawValue: value) {
        case .briefcase: Ph.briefcase.bold
        case .code: Ph.code.bold
        case .database: Ph.database.bold
        case .folder: Ph.folder.bold
        case .wrench: Ph.wrench.bold
        case .key: Ph.key.bold
        case .paintBrush: Ph.paintBrush.bold
        case .image: Ph.image.bold
        case .palette: Ph.palette.bold
        case .gridFour: Ph.gridFour.bold
        case .magicWand: Ph.magicWand.bold
        case .cursorClick: Ph.cursorClick.bold
        case .tag: Ph.tag.bold
        case .stack: Ph.stack.bold
        case .puzzlePiece: Ph.puzzlePiece.bold
        case .lightbulb: Ph.lightbulb.bold
        case .bookOpen: Ph.bookOpen.bold
        case .envelope: Ph.envelope.bold
        case .megaphone: Ph.megaphone.bold
        case .chatCircle: Ph.chatCircle.bold
        case .musicNote: Ph.musicNote.bold
        case .heart: Ph.heart.bold
        case .mapPin: Ph.mapPin.bold
        case .leaf: Ph.leaf.bold
        case .flame: Ph.flame.bold
        case .moon: Ph.moon.bold
        case .lock: Ph.lock.bold
        case .none:
            Text(TagSymbol.fallbackEmoji)
                .font(.system(size: size))
        }
    }
}

struct SymbolPickerView: View {
    @Binding var symbolStorageValue: String
    var showsClearButton = true

    @State private var selectedTab: SymbolTab = .icons
    @State private var emojiText = ""

    enum SymbolTab: String, CaseIterable, Identifiable {
        case emojis = "Emojis"
        case icons = "Icons"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Symbol type", selection: $selectedTab) {
                    ForEach(SymbolTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                Spacer()
                if showsClearButton {
                    Button {
                        symbolStorageValue = ""
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .help("Clear symbol")
                }
            }

            switch selectedTab {
            case .emojis:
                HStack(spacing: 8) {
                    TextField("Emoji", text: $emojiText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onSubmit(applyEmoji)
                    Button("Use") { applyEmoji() }
                        .disabled(emojiText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Text("Paste any emoji. It will be used anywhere the tag or collection appears.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .icons:
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(PhosphorTagIcon.groups, id: \.title) { group in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(group.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 7), count: 6), spacing: 7) {
                                    ForEach(group.icons) { icon in
                                        Button {
                                            symbolStorageValue = TagSymbol(kind: .phosphor, value: icon.rawValue).storageValue
                                        } label: {
                                            TagSymbolView(
                                                symbol: TagSymbol(kind: .phosphor, value: icon.rawValue),
                                                size: 17
                                            )
                                            .frame(width: 30, height: 30)
                                            .background(isSelected(icon) ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.10))
                                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                        .help(icon.title)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 220)
            }
        }
        .padding(14)
        .frame(width: 286)
        .onAppear {
            if let symbol = TagSymbol(storageValue: symbolStorageValue), symbol.kind == .emoji {
                emojiText = symbol.value
                selectedTab = .emojis
            }
        }
    }

    private func applyEmoji() {
        let trimmed = emojiText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        symbolStorageValue = TagSymbol(kind: .emoji, value: String(trimmed.prefix(4))).storageValue
    }

    private func isSelected(_ icon: PhosphorTagIcon) -> Bool {
        TagSymbol(storageValue: symbolStorageValue) == TagSymbol(kind: .phosphor, value: icon.rawValue)
    }
}
