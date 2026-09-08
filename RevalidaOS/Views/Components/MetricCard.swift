import SwiftUI

struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String?
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Image(systemName: systemImage).foregroundStyle(.tint); Spacer(); Text(title).font(.caption).foregroundStyle(.secondary) }
            Text(value).font(.title2.bold()).contentTransition(.numericText())
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
