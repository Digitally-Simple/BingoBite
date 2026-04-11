import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CardDesignControlsView: View {
    @Binding var settings: CardDesignSettings
    @Binding var selectedOverlayID: String?

    private var availableFonts: [String] {
        ["System"] + NSFontManager.shared.availableFontFamilies.sorted()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                cellContentSection
                typographySection
                colorsSection
                cardTitleSection
                freeSpaceSection
                pageLayoutSection
                imageOverlaysSection
            }
            .padding()
        }
    }

    // MARK: - Cell Content

    private var cellContentSection: some View {
        GroupBox("Cell Content") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Show Track Name", isOn: $settings.showTrackName)
                Toggle("Show Artist Name", isOn: $settings.showArtistName)
                Toggle("Show Album Name", isOn: $settings.showAlbumName)
                Toggle("Show Artwork", isOn: $settings.showArtwork)
                    .disabled(settings.useArtworkAsBackground)
                Toggle("Album Cover as Cell Background", isOn: $settings.useArtworkAsBackground)

                if settings.useArtworkAsBackground {
                    HStack {
                        Text("Background Opacity")
                        Spacer()
                        Slider(value: $settings.artworkBackgroundOpacity, in: 0.1...1.0, step: 0.05)
                            .frame(maxWidth: 120)
                        Text(String(format: "%.0f%%", settings.artworkBackgroundOpacity * 100))
                            .font(.caption)
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Typography

    private var typographySection: some View {
        GroupBox("Typography") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Font", selection: $settings.fontFamily) {
                    ForEach(availableFonts, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }

                Picker("Weight", selection: $settings.fontWeight) {
                    Text("Regular").tag("regular")
                    Text("Medium").tag("medium")
                    Text("Semibold").tag("semibold")
                    Text("Bold").tag("bold")
                }

                HStack {
                    Text("Track Name Size")
                    Spacer()
                    Stepper(
                        "\(Int(settings.trackNameFontSize)) pt",
                        value: $settings.trackNameFontSize,
                        in: 6...24,
                        step: 1
                    )
                }

                HStack {
                    Text("Artist Size")
                    Spacer()
                    Stepper(
                        "\(Int(settings.artistNameFontSize)) pt",
                        value: $settings.artistNameFontSize,
                        in: 6...20,
                        step: 1
                    )
                }

                HStack {
                    Text("Album Size")
                    Spacer()
                    Stepper(
                        "\(Int(settings.albumNameFontSize)) pt",
                        value: $settings.albumNameFontSize,
                        in: 6...18,
                        step: 1
                    )
                }

                Divider()

                Picker("Text Overflow", selection: $settings.shrinkTextToFit) {
                    Text("Truncate (...)").tag(false)
                    Text("Shrink to Fit").tag(true)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Colors

    private var colorsSection: some View {
        GroupBox("Colors") {
            VStack(alignment: .leading, spacing: 8) {
                ColorPicker("Cell Background", selection: hexColorBinding($settings.cellBackgroundHex))
                ColorPicker("Cell Text", selection: hexColorBinding($settings.cellTextColorHex))
                ColorPicker("Header Background", selection: hexColorBinding($settings.headerBackgroundHex))
                ColorPicker("Header Text", selection: hexColorBinding($settings.headerTextColorHex))
                ColorPicker("Card Background", selection: hexColorBinding($settings.cardBackgroundHex))
                ColorPicker("Border", selection: hexColorBinding($settings.borderColorHex))

                HStack {
                    Text("Border Width")
                    Spacer()
                    Stepper(
                        String(format: "%.1f pt", settings.borderWidth),
                        value: $settings.borderWidth,
                        in: 0...4,
                        step: 0.5
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Card Title

    private var cardTitleSection: some View {
        GroupBox("Card Title") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Title", text: $settings.cardTitle)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Text("Title Size")
                    Spacer()
                    Stepper(
                        "\(Int(settings.cardTitleFontSize)) pt",
                        value: $settings.cardTitleFontSize,
                        in: 14...48,
                        step: 2
                    )
                }

                ColorPicker("Title Color", selection: hexColorBinding($settings.cardTitleColorHex))
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Free Space

    private var freeSpaceSection: some View {
        GroupBox("Free Space") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Text", text: $settings.freeSpaceText)
                    .textFieldStyle(.roundedBorder)

                ColorPicker("Background", selection: hexColorBinding($settings.freeSpaceColorHex))
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Page Layout

    private var pageLayoutSection: some View {
        GroupBox("Page Layout") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Cards Per Page", selection: $settings.cardsPerPage) {
                    Text("1").tag(1)
                    Text("2").tag(2)
                    Text("4").tag(4)
                }

                Picker("Orientation", selection: $settings.pageOrientation) {
                    Text("Portrait").tag("portrait")
                    Text("Landscape").tag("landscape")
                }

                Toggle("Show Card Numbers", isOn: $settings.showCardNumbers)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Image Overlays

    private var imageOverlaysSection: some View {
        GroupBox("Image Overlays") {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    addImage()
                } label: {
                    Label("Add Image", systemImage: "plus.circle")
                }

                if !settings.imageOverlays.isEmpty {
                    Divider()
                    overlayList
                }

                if let selectedID = selectedOverlayID,
                   let index = settings.imageOverlays.firstIndex(where: { $0.id == selectedID }) {
                    Divider()
                    selectedOverlayControls(index: index)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var overlayList: some View {
        ForEach(Array(settings.imageOverlays.enumerated()), id: \.element.id) { index, overlay in
            overlayRow(index: index, overlay: overlay)
        }
    }

    private func overlayRow(index: Int, overlay: ImageOverlay) -> some View {
        HStack(spacing: 8) {
            if let nsImage = overlay.cachedImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .frame(width: 32, height: 32)
            }

            Text(overlay.label)
                .font(.caption)
                .lineLimit(1)

            Spacer()

            if selectedOverlayID == overlay.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.caption)
            }

            Button {
                if selectedOverlayID == overlay.id {
                    selectedOverlayID = nil
                }
                ImageOverlay.clearCache(for: overlay.id)
                settings.imageOverlays.remove(at: index)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedOverlayID = overlay.id
        }
        .padding(.vertical, 2)
        .background(
            selectedOverlayID == overlay.id
                ? Color.accentColor.opacity(0.1)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func selectedOverlayControls(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Label", text: $settings.imageOverlays[index].label)
                .textFieldStyle(.roundedBorder)
                .font(.caption)

            HStack {
                Text("Scale")
                Spacer()
                Slider(
                    value: $settings.imageOverlays[index].normalizedScale,
                    in: 0.05...1.0,
                    step: 0.01
                )
                .frame(maxWidth: 120)
                Text(String(format: "%.0f%%", settings.imageOverlays[index].normalizedScale * 100))
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 36, alignment: .trailing)
            }

            HStack {
                Text("Opacity")
                Spacer()
                Slider(
                    value: $settings.imageOverlays[index].opacity,
                    in: 0.1...1.0,
                    step: 0.05
                )
                .frame(maxWidth: 120)
                Text(String(format: "%.0f%%", settings.imageOverlays[index].opacity * 100))
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 36, alignment: .trailing)
            }
        }
    }

    // MARK: - Image Picker

    private func addImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an image to overlay on your bingo cards"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let imageData = ImageOverlay.downsampledData(from: url) else { return }

        let fileName = url.deletingPathExtension().lastPathComponent
        var overlay = ImageOverlay(imageData: imageData)
        overlay.label = fileName
        settings.imageOverlays.append(overlay)
        selectedOverlayID = overlay.id
    }
}
