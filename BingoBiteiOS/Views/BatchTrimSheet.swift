import SwiftUI
import SwiftData

/// Applies one start/end trim to a whole selection of songs at once.
///
/// The point is consistency across a night: every track drops in at the same
/// spot and cuts at the same length, without opening each one.
struct BatchTrimSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let songs: [Song]
    var onApplied: (SoundByteService.BatchResult) -> Void

    @State private var startTime: TimeInterval = 0
    @State private var clipLength: TimeInterval = 30
    @State private var result: SoundByteService.BatchResult?
    @State private var showRemoveConfirmation = false

    private var endTime: TimeInterval { startTime + clipLength }

    /// The shortest song decides what actually fits — anything longer than this
    /// gets clamped, so it's worth showing up front.
    private var shortestDuration: TimeInterval? {
        songs.compactMap(\.duration).filter { $0 > 0 }.min()
    }

    private var clampedCount: Int {
        songs.filter { song in
            guard let duration = song.duration, duration > 0 else { return false }
            return endTime > duration
        }.count
    }

    private var tooShortCount: Int {
        songs.filter { song in
            guard let duration = song.duration, duration > 0 else { return false }
            return startTime >= duration
        }.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let result {
                            resultCard(result)
                        } else {
                            trimCard
                            warningsCard
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Trim \(songs.count) Song\(songs.count == 1 ? "" : "s")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(result == nil ? "Cancel" : "Done") {
                        if let result { onApplied(result) }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if result == nil {
                        Button("Apply") { apply() }
                            .disabled(songs.isEmpty || clipLength <= 0)
                    }
                }
            }
            .confirmationDialog(
                "Clear trims on \(songs.count) song\(songs.count == 1 ? "" : "s")?",
                isPresented: $showRemoveConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear Trims", role: .destructive) {
                    SoundByteService.removeBatch(from: songs, in: context)
                    onApplied(SoundByteService.BatchResult())
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("They'll play in full again.")
            }
        }
    }

    // MARK: - Editing

    private var trimCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading("Clip")

            timeRow(
                title: "Start at",
                value: $startTime,
                range: 0...600
            )
            timeRow(
                title: "Play for",
                value: $clipLength,
                range: 1...600
            )

            DetailRow(label: "Ends at", value: Self.timeLabel(endTime))

            Text("Every selected song will start at \(Self.timeLabel(startTime)) and play for \(Self.timeLabel(clipLength)).")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(role: .destructive) {
                showRemoveConfirmation = true
            } label: {
                Label("Clear Trims Instead", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.glass)
        }
        .glassCard()
    }

    @ViewBuilder
    private var warningsCard: some View {
        if clampedCount > 0 || tooShortCount > 0 {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeading("Heads up")

                if clampedCount > 0 {
                    Label(
                        "\(clampedCount) song\(clampedCount == 1 ? " is" : "s are") shorter than \(Self.timeLabel(endTime)) — \(clampedCount == 1 ? "it" : "they") will end at the song's own end instead.",
                        systemImage: "arrow.down.right.and.arrow.up.left"
                    )
                    .font(.caption)
                }

                if tooShortCount > 0 {
                    Label(
                        "\(tooShortCount) song\(tooShortCount == 1 ? " is" : "s are") shorter than the start time and will be skipped.",
                        systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                if let shortestDuration {
                    Text("Shortest song in the selection: \(Self.timeLabel(shortestDuration)).")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .glassCard(tint: tooShortCount > 0 ? .orange : nil)
        }
    }

    private func timeRow(title: String, value: Binding<TimeInterval>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(Self.timeLabel(value.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Stepper(title, value: value, in: range, step: 1)
                    .labelsHidden()
            }
            Slider(value: value, in: range, step: 1)
        }
    }

    // MARK: - Result

    private func resultCard(_ result: SoundByteService.BatchResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading("Applied")
            DetailRow(label: "Trimmed", value: "\(result.applied.count)")
            if !result.clamped.isEmpty {
                DetailRow(label: "Shortened to fit", value: "\(result.clamped.count)")
            }
            if !result.tooShort.isEmpty {
                Text("\(result.tooShort.count) song\(result.tooShort.count == 1 ? " was" : "s were") skipped for being shorter than the start time.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .glassCard()
    }

    // MARK: - Actions

    private func apply() {
        result = SoundByteService.applyBatch(
            to: songs,
            startTime: startTime,
            endTime: endTime,
            in: context
        )
    }

    static func timeLabel(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
