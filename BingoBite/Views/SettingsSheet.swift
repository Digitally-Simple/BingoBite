import SwiftUI
import SwiftData

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Settings")
                .font(.title2)
                .fontWeight(.semibold)

            GroupBox("About") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Version:")
                            .foregroundStyle(.secondary)
                        Text(version)
                            .monospacedDigit()
                    }
                    Text("Playlists and games are stored on this Mac. Songs are read from the source folder you picked when creating each playlist.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420, height: 300)
    }
}
