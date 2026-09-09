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
                Button("Ampliar tabela em imagem") {
                    preview = PreviewImage(url: fallback, caption: item.caption)
                }
                .buttonStyle(.bordered)
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

    var body: some View {
        ScrollView(.horizontal) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Array(table.columns.enumerated()), id: \.offset) { _, column in
                        Text(column)
                            .font(.subheadline.bold())
                            .padding(10)
                            .frame(minWidth: 120, alignment: .leading)
                            .background(Color.accentColor.opacity(0.12))
                            .overlay(Rectangle().stroke(Color.secondary.opacity(0.15), lineWidth: 0.5))
                    }
                }
                ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(cell)
                                .font(.subheadline)
                                .padding(10)
                                .frame(minWidth: 120, alignment: .leading)
                                .background(rowIndex.isMultiple(of: 2) ? Color.clear : Color.secondary.opacity(0.06))
                                .overlay(Rectangle().stroke(Color.secondary.opacity(0.15), lineWidth: 0.5))
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
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
