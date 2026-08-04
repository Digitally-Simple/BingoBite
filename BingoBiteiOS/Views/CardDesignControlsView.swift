import SwiftUI
import PhotosUI

struct CardDesignControlsView: View {
    @Binding var settings: CardDesignSettings
    @Binding var selectedOverlayID: String?
    @Binding var setID: String

    @State private var photoItem: PhotosPickerItem?
    @State private var showFileImporter = false

    var body: some View {
        Form {
            cellContent
            typography
            colors
            titleSection
            cardNumbers
            setIdentity
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

    /// Identifies a printed deck so cards from different decks can be sorted
    /// back apart after they get shuffled together.
    private var setIdentity: some View {
        Section {
            HStack {
                Text("Set code")
                Spacer()
                TextField("AB", text: $setID)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .frame(width: 90)
                    .onChange(of: setID) { _, newValue in
                        // Codes are read off paper and typed back in, so keep
                        // them short and unambiguous.
                        let cleaned = newValue.uppercased().filter { $0.isLetter || $0.isNumber }
                        if cleaned != newValue { setID = String(cleaned.prefix(4)) }
                        else if cleaned.count > 4 { setID = String(cleaned.prefix(4)) }
                    }
            }

            Toggle("Print set code on cards", isOn: $settings.showSetID)
                .disabled(!settings.showCardNumbers || setID.isEmpty)
        } header: {
            Text("Card Set")
        } footer: {
            Text(setIDSummary)
        }
    }

    private var setIDSummary: String {
        guard settings.showCardNumbers else {
            return "Card numbers are off, so nothing is printed in the corner of each card."
        }
        guard settings.showSetID, !setID.isEmpty else {
            return "Cards print as “Card #1”. Turn on the set code to print “\(setID.isEmpty ? "AB" : setID)-1” instead, so decks shuffled together can be sorted apart."
        }
        return "Cards print as “\(setID)-1”, “\(setID)-2”… Give each deck its own code so they can be told apart once mixed."
    }

    private var pageLayout: some View {
        Section {
            Picker("Cards per sheet", selection: $settings.cardsPerPage) {
                Text("1").tag(1)
                Text("2").tag(2)
                Text("4").tag(4)
            }
            .pickerStyle(.segmented)

            Picker("Paper orientation", selection: $settings.pageOrientation) {
                Text("Portrait").tag("portrait")
                Text("Landscape").tag("landscape")
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Printing")
        } footer: {
            Text("How the cards sit on a sheet of US Letter paper when you print or export a PDF. \(printingSummary)")
        }
    }

    /// Spells out the resulting arrangement, since "2 per sheet" means side by
    /// side on landscape and stacked on portrait.
    private var printingSummary: String {
        let grid = settings.grid
        let shape = settings.isLandscape ? "wider than they are tall" : "taller than they are wide"
        switch settings.cardsPerPage {
        case 1:  return "One card fills each sheet, \(shape)."
        case 2:  return grid.columns == 2
            ? "Two cards side by side, each \(shape)."
            : "Two cards stacked, each \(shape)."
        default: return "Four cards in a 2×2 grid, each \(shape)."
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
