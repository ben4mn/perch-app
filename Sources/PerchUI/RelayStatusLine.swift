import PerchKit
import SwiftUI

/// Whether Perch is reading from the Relay, and if not, why: a dot (or a spinner while it waits), a short
/// title, and a line on what to do. Settings shows it above the address and token.
public struct RelayStatusLine: View {
    @ObservedObject var model: AppModel
    @Environment(\.perchTheme) private var theme

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        let status = model.relayStatus
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Group {
                if status == .connecting {
                    ProgressView().controlSize(.small)
                } else {
                    Circle().fill(color(status)).frame(width: 8, height: 8)
                }
            }
            .frame(width: 16)
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            VStack(alignment: .leading, spacing: 1) {
                Text(status.title).font(.perchStyle(.body).weight(.semibold)).foregroundStyle(status.isConnected ? theme.success : theme.text)
                Text(status.detail).font(.perchStyle(.caption)).foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .motion(Motion.smooth, value: status)
    }

    private func color(_ status: RelayStatus) -> Color {
        switch status {
        case .connected: theme.success
        case .off, .connecting: theme.textMuted
        case .refused, .unreachable, .failed: theme.danger
        }
    }
}
