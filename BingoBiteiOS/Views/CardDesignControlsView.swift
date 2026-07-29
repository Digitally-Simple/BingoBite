import SwiftUI
import PhotosUI

struct CardDesignControlsView: View {
    @Binding var settings: CardDesignSettings
    @Binding var selectedOverlayID: String?

    @State private var photoItem: PhotosPickerItem?
    @State private var showFileImporter = false

    var body: some View {
        Form {
            cellContent
            typography
            colors
            titleSection
            cardNumbers
            freeSpace
            pageLayout
            overlays
        }
        .formStyle(.grouped)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await addOverlay(from: item) }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = ImageOverlay.downsampledData(from: url) else { return }
            appendOverlay(data: data, label: url.deletingPathExtension().lastPathComponent)
        }
    }

    // MARK: - Cell content

    private var cellContent: some View {
        Section("Cell Content") {
            Toggle("Track name", isOn: $settings.showTrackName)
            Toggle("Artist name", isOn: $settings.showArtistName)
            Toggle("Album name", isOn: $settings.showAlbumName)
            Toggle("Artwork thumbnail", isOn: $settings.showArtwork)
                .disabled(settings.useArtworkAsBackground)
            Toggle("Artwork as cell background", isOn: $settings.useArtworkAsBackground)

            if settings.useArtworkAsBackground {
                percentSlider("Background opacity", value: $settings.artworkBackgroundOpacity, range: 0.1...1.0)
            }
        }
    }

    // MARK: - Typography

    private var typography: some View {
        Section("Typography") {
            Picker("Font", selection: $settings.fontFamily) {
                ForEach(PlatformFonts.families, id: \.self) { Text($0).tag($0) }
            }

            Picker("Weight", selection: $settings.fontWeight) {
                Text("Regular").tag("regular")
                Text("Medium").tag("medium")
                Text("Semibold").tag("semibold")
                Text("Bold").tag("bold")
            }

            pointStepper("Track size", value: $settings.trackNameFontSize, range: 6...24)
            pointStepper("Artist size", value: $settings.artistNameFontSize, range: 6...20)
            pointStepper("Album size", value: $settings.albumNameFontSize, range: 6...18)

            Picker("Overflow", selection: $settings.shrinkTextToFit) {
                Text("Truncate").tag(false)
                Text("Shrink to fit").tag(true)
            }
        }
    }

    // MARK: - Colors

    private var colors: some View {
        Section("Colors") {
            ColorPicker("Cell background", selection: hexColorBinding($settings.cellBackgroundHex))
            ColorPicker("Cell text", selection: hexColorBinding($settings.cellTextColorHex))
            ColorPicker("Header background", selection: hexColorBinding($settings.headerBackgroundHex))
            ColorPicker("Header text", selection: hexColorBinding($settings.headerTextColorHex))
            ColorPicker("Card background", selection: hexColorBinding($settings.cardBackgroundHex))
            ColorPicker("Border", selection: hexColorBinding($settings.borderColorHex))

            Stepper(
                "Border width: \(settings.borderWidth, specifier: "%.1f") pt",
                value: $settings.borderWidth,
                in: 0...4,
                step: 0.5
            )
        }
    }

    // MARK: - Title / numbers / free space

    private var titleSection: some View {
        Section("Card Title") {
            TextField("Title", text: $settings.cardTitle)
            pointStepper("Title size", value: $settings.cardTitleFontSize, range: 14...48, step: 2)
            ColorPicker("Title color", selection: hexColorBinding($settings.cardTitleColorHex))
        }
    }

    private var cardNumbers: some View {
        Section("Card Number") {
            Toggle("Show card number", isOn: $settings.showCardNumbers)
            if settings.showCardNumbers {
                pointStepper("Size", value: $settings.cardNumberFontSize, range: 6...20)
                ColorPicker("Color", selection: hexColorBinding($settings.cardNumberColorHex))
            }
        }
    }

    private var freeSpace: some View {
        Section("Free Space") {
            TextField("Text", text: $settings.freeSpaceText)
            ColorPicker("Background", selection: hexColorBinding($settings.freeSpaceColorHex))
        }
    }

    private var pageLayout: some View {
        Section("Page Layout") {
            Picker("Cards per page", selection: $settings.cardsPerPage) {
                Text("1").tag(1)
                Text("2").tag(2)
                Text("4").tag(4)
            }
            .pickerStyle(.segmented)

            Picker("Orientation", selection: $settings.pageOrientation) {
                Text("Portrait").tag("portrait")
                Text("Landscape").tag("landscape")
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Overlays

    private var overlays: some View {
        Section {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Add from Photos", systemImage: "photo.on.rectangle")
            }
            Button("Add from Files", systemImage: "folder") {
                showFileImporter = true
            }

            ForEach(Array(settings.imageOverlays.enumerated()), id: \.element.id) { index, overlay in
                overlayRow(index: index, overlay: overlay)
            }
            .onDelete { offsets in
                for index in offsets {
                    let overlay = settings.imageOverlays[index]
                    if selectedOverlayID == overlay.id { selectedOverlayID = nil }
                    ImageOverlay.clearCache(for: overlay.id)
                }
                settings.imageOverlays.remove(atOffsets: offsets)
            }

            if let id = selectedOverlayID,
               let index = settings.imageOverlays.firstIndex(where: { $0.id == id }) {
                TextField("Label", text: $settings.imageOverlays[index].label)
                percentSlider("Scale", value: $settings.imageOverlays[index].normalizedScale, range: 0.05...1.0)
                percentSlider("Opacity", value: $settings.imageOverlays[index].opacity, range: 0.1...1.0)
            }
        } header: {
            Text("Image Overlays")
        } footer: {
            if !settings.imageOverlays.isEmpty {
                Text("Tap an overlay to select it, then drag it around the preview.")
            }
        }
    }

    private func overlayRow(index: Int, overlay: ImageOverlay) -> some View {
        Button {
            selectedOverlayID = overlay.id
        } label: {
            HStack(spacing: 12) {
                if let image = overlay.cachedImage {
                    Image(platformImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.quaternary)
                        .frame(width: 36, height: 36)
                }

                Text(overlay.label)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Spacer()

                if selectedOverlayID == overlay.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func addOverlay(from item: PhotosPickerItem) async {
        guard let raw = try? await item.loadTransferable(type: Data.self),
              let data = ImageOverlay.downsampledData(from: raw) else { return }
        await MainActor.run {
            appendOverlay(data: data, label: "Image \(settings.imageOverlays.count + 1)")
            photoItem = nil
        }
    }

    private func appendOverlay(data: Data, label: String) {
        var overlay = ImageOverlay(imageData: data)
        overlay.label = label
        settings.imageOverlays.append(overlay)
        selectedOverlayID = overlay.id
    }

    // MARK: - Reusable controls

    private func pointStepper(
        _ label: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        step: CGFloat = 1
    ) -> some View {
        Stepper("\(label): \(Int(value.wrappedValue)) pt", value: value, in: range, step: step)
    }

    private func percentSlider(
        _ label: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }
}
