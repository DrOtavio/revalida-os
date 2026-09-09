import SwiftUI

struct QuestionRichContentView: View {
    let media: [QuestionMedia]
    @State private var preview: PreviewImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(media) { item in
                if item.isImage {
                    imageCard(item)
                } else if item.isTable {
                    tableCard(item)
                }
            }
        }
        .sheet(item: $preview) { item in
            NavigationStack {
                ZoomableRemoteImage(url: item.url, caption: item.caption)
                    .navigationTitle("Imagem")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private func imageCard(_ item: QuestionMedia) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = item.title, !title.isEmpty {
                Text(title).font(.headline)
            }

            Button {
                if let url = item.resolvedURL {
                    preview = PreviewImage(url: url, caption: item.caption)
                }
            } label: {
                RemoteImageCard(url: item.resolvedURL, altText: item.altText)
            }
            .buttonStyle(.plain)

            if let caption = item.caption, !caption.isEmpty {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func tableCard(_ item: QuestionMedia) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = item.title, !title.isEmpty {
                Text(title).font(.headline)
            }
            if let table = item.table {
                QuestionTableView(table: table)
            }
            if let caption = item.caption, !caption.isEmpty {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let fallback = item.resolvedURL {
                Button("Ver tabela original") {
                    preview = PreviewImage(url: fallback, caption: item.caption)
                }
                .buttonStyle(.plain)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.tint)
            }
        }
    }
}

private struct RemoteImageCard: View {
    let url: URL?
    let altText: String?

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.10))
                            ProgressView("Carregando imagem...")
                        }
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    case .failure:
                        ZStack {
                            RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.10))
                            VStack(spacing: 8) {
                                Image(systemName: "photo.badge.exclamationmark")
                                    .font(.title2)
                                Text(altText ?? "Não foi possível carregar a imagem.")
                                    .font(.footnote)
                                    .multilineTextAlignment(.center)
                            }
                            .padding()
                        }
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.10))
                    Text(altText ?? "Imagem não configurada.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 180)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}

private struct QuestionTableView: View {
    let table: QuestionTable
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: table.columns.count >= 3) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(table.columns.enumerated()), id: \.offset) { index, column in
                        tableCell(
                            column,
                            column: index,
                            isHeader: true,
                            isFirstColumn: false,
                            rowIndex: nil
                        )
                    }
                }

                ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(Array(table.columns.indices), id: \.self) { columnIndex in
                            let value = columnIndex < row.count ? row[columnIndex] : ""
                            tableCell(
                                value,
                                column: columnIndex,
                                isHeader: false,
                                isFirstColumn: columnIndex == 0,
                                rowIndex: rowIndex
                            )
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    @ViewBuilder
    private func tableCell(
        _ text: String,
        column: Int,
        isHeader: Bool,
        isFirstColumn: Bool,
        rowIndex: Int?
    ) -> some View {
        Text(text)
            .font(isHeader ? .subheadline.bold() : (isFirstColumn ? .subheadline.weight(.medium) : .subheadline))
            .foregroundStyle(isHeader ? Color.primary : Color.primary)
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: columnWidth(column), alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(cellBackground(isHeader: isHeader, rowIndex: rowIndex))
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(borderColor)
                    .frame(width: 0.5)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(borderColor)
                    .frame(height: 0.5)
            }
    }

    private func columnWidth(_ index: Int) -> CGFloat {
        switch table.columns.count {
        case 1:
            return 300
        case 2:
            return index == 0 ? 205 : 145
        case 3:
            switch index {
            case 0: return 165
            case 1: return 135
            default: return 175
            }
        default:
            return index == 0 ? 170 : 145
        }
    }

    private func cellBackground(isHeader: Bool, rowIndex: Int?) -> Color {
        if isHeader {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.24 : 0.14)
        }
        guard let rowIndex else { return .clear }
        return rowIndex.isMultiple(of: 2)
            ? Color.secondary.opacity(colorScheme == .dark ? 0.035 : 0.025)
            : Color.secondary.opacity(colorScheme == .dark ? 0.09 : 0.055)
    }

    private var borderColor: Color {
        Color.secondary.opacity(colorScheme == .dark ? 0.25 : 0.20)
    }
}

private struct ZoomableRemoteImage: View {
    let url: URL
    let caption: String?
    @Environment(\.dismiss) var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        VStack {
            ScrollView([.horizontal, .vertical]) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView("Carregando...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(scale)
                            .gesture(MagnificationGesture().onChanged { scale = max(1, $0) })
                            .padding()
                    case .failure:
                        ContentUnavailableView("Falha ao carregar", systemImage: "exclamationmark.triangle")
                    @unknown default:
                        EmptyView()
                    }
                }
            }
            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Fechar") { dismiss() }
            }
        }
    }
}

private struct PreviewImage: Identifiable {
    let id = UUID()
    let url: URL
    let caption: String?
}
