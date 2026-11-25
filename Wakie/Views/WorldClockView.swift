//
//  WorldClockView.swift
//  Wakie
//

import SwiftUI
import MapKit
import PhotosUI

struct WorldClockView: View {
    @Environment(AppModel.self) private var model
    @State private var isAdding = false
    @State private var isEditing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                TimelineView(.everyMinute) { context in
                    VStack(spacing: 18) {
                        ForEach(model.cities) { city in
                            EditableCityRow(
                                city: city,
                                now: context.date,
                                index: model.cities.firstIndex(of: city) ?? 0,
                                isEditing: isEditing,
                                onDelete: { withAnimation(.bouncy) { model.removeCity(city) } }
                            )
                            // Swipe left to delete, like the Alarms tab.
                            .swipeActions(edge: .trailing, allowsFullSwipe: !isEditing) {
                                Button(role: .destructive) {
                                    withAnimation(.bouncy) { model.removeCity(city) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                        }
                        .reorderable()
                    }
                    // In edit mode, press and drag a card to reposition it.
                    .reorderContainer(for: WorldCity.self, isEnabled: isEditing) { difference in
                        let target: String? = switch difference.destination.position {
                        case let .before(id): id
                        case .end: nil
                        }
                        withAnimation(.bouncy(duration: 0.45, extraBounce: 0.15)) {
                            model.moveCities(difference.sources, before: target)
                        }
                    }
                    // A soft tap each time a card settles into a new spot.
                    .sensoryFeedback(.impact(flexibility: .soft), trigger: model.cities.map(\.id))
                }
                if model.cities.isEmpty {
                    Text("Tap + to add a city.")
                        .font(.wakie(15, .semibold))
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            // Leave room so the last card can scroll clear of the flight path.
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .swipeActionsContainer()
        .background {
            // Fixed decoration: stays put while the cities scroll over it.
            ZStack(alignment: .bottom) {
                AppBackground()
                FlightPath()
                    .frame(height: 70)
                    .padding(.horizontal, 50)
                    .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $isAdding) {
            AddCitySheet()
                .presentationDetents([.medium])
        }
        .onChange(of: model.cities.isEmpty) { _, empty in
            if empty { isEditing = false }
        }
        .sensoryFeedback(.selection, trigger: isEditing)
    }

    private var header: some View {
        TabHeader(isEditing: $isEditing, showsEdit: !model.cities.isEmpty, addLabel: "Add city") {
            isAdding = true
        } title: {
            Text("World Clock")
                .font(.wakie(34, .black))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// A city card that, in edit mode, gently wobbles and shows delete and drag controls.
/// The delete badge sits inside the row's frame so the drag preview never clips it.
struct EditableCityRow: View {
    let city: WorldCity
    let now: Date
    let index: Int
    let isEditing: Bool
    let onDelete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var model
    @State private var isPickingPhoto = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isFetchingPhoto = false


    var body: some View {
        ZStack(alignment: .topLeading) {
            CityCard(city: city, now: now)
                // Make room for the badge inside this row's bounds while editing.
                .padding(.top, isEditing ? 12 : 0)
                .padding(.leading, isEditing ? 12 : 0)
            if isEditing {
                Button(action: onDelete) {
                    Image(systemName: "minus")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Theme.danger))
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Delete \(city.name)")
                .transition(.scale(scale: 0.3).combined(with: .opacity))
            }
        }
        .modifier(Wobble(isActive: isEditing && !reduceMotion, seed: Double(index)))
        // No resting tilt: the cards are Liquid Glass, which renders cleanly only when unrotated.
        .scaleEffect(isEditing ? 0.98 : 1)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isEditing)
        .overlay(alignment: .trailing) {
            if isFetchingPhoto {
                ProgressView()
                    .padding(.trailing, 24)
            }
        }
        .contextMenu {
            // Long-press is used for dragging while editing.
            if !isEditing {
                Button("Choose from Photos", systemImage: "photo.on.rectangle") { isPickingPhoto = true }
                Button("Find a Photo Online", systemImage: "globe") {
                    isFetchingPhoto = true
                    Task {
                        await model.fetchPhoto(for: city.id)
                        isFetchingPhoto = false
                    }
                }
                Button("Remove \(city.name)", systemImage: "trash", role: .destructive, action: onDelete)
            }
        }
        .photosPicker(isPresented: $isPickingPhoto, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    model.setPhoto(data: data, for: city.id)
                }
                photoItem = nil
            }
        }
    }
}

/// Home-screen style jiggle that signals the cards can be rearranged.
private struct Wobble: ViewModifier {
    let isActive: Bool
    let seed: Double

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isActive)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            content
                .rotationEffect(.degrees(isActive ? sin(t * 11 + seed * 1.7) * 0.7 : 0))
                .offset(y: isActive ? sin(t * 9 + seed) * 0.8 : 0)
        }
    }
}

struct CityCard: View {
    let city: WorldCity
    let now: Date

    private var timeText: String {
        now.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: city.timeZone))
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(city.name)
                        .font(.wakie(18, .heavy))
                        .lineLimit(1)
                    Text(city.flag)
                        .font(.system(size: 16))
                }
                Text(timeText)
                    .font(.wakie(30, .black))
                    .monospacedDigit()
                Text(offsetText(for: city.timeZone, now: now))
                    .font(.wakie(12, .semibold))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .foregroundStyle(Theme.ink)
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: 112)
        .background(alignment: .trailing) {
            CityBanner(city: city)
                .frame(width: 210, height: 112)
                .clipped()
                .mask(
                    LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.45)],
                                   startPoint: .leading, endPoint: .trailing)
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .liquidGlassCard(radius: 28)
        .accessibilityElement(children: .combine)
    }
}

/// "Today, +4h 30m" style difference between a time zone and the phone's.
func offsetText(for zone: TimeZone, now: Date) -> String {
    let diff = zone.secondsFromGMT(for: now) - TimeZone.current.secondsFromGMT(for: now)
    var calendar = Calendar.current
    calendar.timeZone = zone
    let cityDay = calendar.component(.day, from: now)
    let localDay = Calendar.current.component(.day, from: now)
    let day = cityDay == localDay ? "Today" : (diff > 0 ? "Tomorrow" : "Yesterday")
    guard diff != 0 else { return "\(day), same time" }
    let hours = abs(diff) / 3600
    let minutes = (abs(diff) % 3600) / 60
    let sign = diff > 0 ? "+" : "−"
    return "\(day), \(sign)\(hours)h" + (minutes > 0 ? " \(minutes)m" : "")
}

/// The picture on the right of a city card: the person's photo, built-in art, or a gradient.
struct CityBanner: View {
    let city: WorldCity

    var body: some View {
        if let url = city.photoURL, let image = UIImage(contentsOfFile: url.path(percentEncoded: false)) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if let name = city.banner {
            Image(name)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                // Soft placeholder while the city's photo loads.
                LinearGradient(colors: [Theme.lavender.opacity(0.25), Theme.purple.opacity(0.2)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "building.2.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.white.opacity(0.35))
                    .offset(x: 30, y: 14)
            }
        }
    }
}

/// The dashed flight path with a plane under the city list.
struct FlightPath: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: w * 0.25, y: h))
                    p.addQuadCurve(to: CGPoint(x: w * 0.85, y: h * 0.2), control: CGPoint(x: w * 0.35, y: h * 0.1))
                }
                .stroke(Theme.ink.opacity(0.7), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [6, 7]))
                Image(systemName: "airplane")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.ink.opacity(0.7))
                    .rotationEffect(.degrees(-15))
                    .position(x: w * 0.9, y: h * 0.15)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Add city

/// Asks for a city and country, looks up its time zone and flag, and lets the
/// person attach a photo of the place from their library.
struct AddCitySheet: View {
    /// Called with the new city after it's saved (e.g. to pick it for an alarm).
    var onAdded: ((WorldCity) -> Void)? = nil

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var cityText = ""
    @State private var countryText = ""
    @State private var lookup: LookupState = .idle
    /// The suggestion the person tapped; its name and country were filled into the fields.
    @State private var selected: PlaceMatch?
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: UIImage?

    private struct PlaceMatch: Equatable, Identifiable {
        var id: String { "\(name)|\(country)|\(timeZoneID)" }
        let name: String
        let country: String
        let flag: String
        let timeZoneID: String
        /// The text that produces this match, used to skip re-searching after autofill.
        var query: String { "\(name), \(country)" }
    }

    private enum LookupState: Equatable {
        case idle, searching, notFound
        case found([PlaceMatch])
    }

    private var query: String {
        [cityText, countryText]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Add a City")
                    .font(.wakie(22, .heavy))
                    .foregroundStyle(Theme.ink)
                Spacer()
                CircleIconButton(systemName: "checkmark", fill: Theme.yellow, foreground: Color(hex: 0x1E1A3C), size: 40) {
                    add()
                }
                .disabled(!canAdd)
                .opacity(canAdd ? 1 : 0.4)
                .accessibilityLabel("Add city")
                CircleIconButton(systemName: "xmark", size: 40) { dismiss() }
                    .accessibilityLabel("Close")
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        field("City", text: $cityText, prompt: "Naples")
                        field("Country", text: $countryText, prompt: "Italy")
                    }
                    preview
                        .frame(minHeight: 58)
                    photoRow
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(AppBackground(showsBlobs: false))
        .presentationDragIndicator(.visible)
        // Look the place up shortly after typing stops.
        .task(id: query) {
            // Tapping a suggestion fills the fields; don't search again for that same text.
            if let selected, selected.query == query { return }
            selected = nil
            guard cityText.trimmingCharacters(in: .whitespaces).count >= 2 else {
                lookup = .idle
                return
            }
            lookup = .searching
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            lookup = await resolve(query)
        }
        .onChange(of: photoItem) { _, item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                photo = UIImage(data: data)
            }
        }
    }

    /// The place that will be added: the tapped suggestion, or the only/first match.
    private var chosenMatch: PlaceMatch? {
        if let selected { return selected }
        if case let .found(matches) = lookup { return matches.first }
        return nil
    }

    private var canAdd: Bool { chosenMatch != nil }

    /// Autocompletes the fields from a suggestion.
    private func choose(_ match: PlaceMatch) {
        selected = match
        cityText = match.name
        countryText = match.country
        lookup = .found([match])
    }

    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: title)
            TextField(title, text: text, prompt: Text(prompt))
                .font(.wakie(17, .semibold))
                .foregroundStyle(Theme.ink)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .wakieCard(radius: 16)
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch lookup {
        case .idle:
            Text("Type a city and country to look up its time.")
                .font(.wakie(13, .semibold))
                .foregroundStyle(Theme.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .searching:
            HStack(spacing: 10) {
                ProgressView()
                Text("Finding \(query)…")
                    .font(.wakie(14, .semibold))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .notFound:
            Label("Couldn't find that place. Check the spelling.", systemImage: "exclamationmark.magnifyingglass")
                .font(.wakie(13, .semibold))
                .foregroundStyle(Theme.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .found(matches):
            VStack(spacing: 8) {
                ForEach(matches) { match in
                    suggestionRow(match)
                }
            }
        }
    }

    private func suggestionRow(_ match: PlaceMatch) -> some View {
        let zone = TimeZone(identifier: match.timeZoneID) ?? .current
        let isSelected = selected == match
        return Button {
            withAnimation(.snappy) { choose(match) }
        } label: {
            TimelineView(.everyMinute) { context in
                HStack(spacing: 12) {
                    Text(match.flag)
                        .font(.system(size: 30))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(match.name), \(match.country)")
                            .font(.wakie(15, .heavy))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Text(offsetText(for: zone, now: context.date))
                            .font(.wakie(12, .semibold))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    Spacer()
                    Text(context.date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)))
                        .font(.wakie(20, .black))
                        .foregroundStyle(Theme.ink)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "arrow.up.left.circle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isSelected ? Theme.purple : Theme.inkSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .wakieCard(radius: 18)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.purple, lineWidth: isSelected ? 2 : 0)
                )
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(match.name), \(match.country)")
        .accessibilityHint(isSelected ? "Selected" : "Fills in the city and country")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Small thumbnail picker for an optional photo of the place.
    private var photoRow: some View {
        HStack(spacing: 14) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                ZStack {
                    if let photo {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 24))
                            .foregroundStyle(Theme.purple)
                    }
                }
                .frame(width: 84, height: 64)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.lavender, style: StrokeStyle(lineWidth: 2, dash: photo == nil ? [6, 5] : []))
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(photo == nil ? "Choose a photo of the place" : "Change photo")
            VStack(alignment: .leading, spacing: 2) {
                Text("Photo of the place")
                    .font(.wakie(15, .bold))
                    .foregroundStyle(Theme.ink)
                Text(photo == nil ? "Optional · we'll find one online if you skip" : "Shown on the city's card")
                    .font(.wakie(12, .semibold))
                    .foregroundStyle(Theme.inkSecondary)
            }
            Spacer()
            if photo != nil {
                Button {
                    photo = nil
                    photoItem = nil
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.danger)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove photo")
            }
        }
    }

    /// Geocodes "City, Country" into up to three distinct places with flag and time zone.
    private func resolve(_ query: String) async -> LookupState {
        guard let request = MKGeocodingRequest(addressString: query) else { return .notFound }
        let items: [MKMapItem] = await withCheckedContinuation { continuation in
            request.getMapItems { items, _ in
                continuation.resume(returning: items ?? [])
            }
        }
        let typedCity = cityText.trimmingCharacters(in: .whitespacesAndNewlines)
        let typedCountry = countryText.trimmingCharacters(in: .whitespacesAndNewlines)
        var matches: [PlaceMatch] = []
        for item in items {
            guard let zone = item.timeZone else { continue }
            let address = item.addressRepresentations
            let country = address?.regionName ?? typedCountry
            // Maps sometimes has no region code (e.g. Jammu), so fall back to the country name.
            let flag = address?.region.map { WorldCity.flag(forRegionCode: $0.identifier) }
                ?? WorldCity.bestFlag(country: country, timeZoneID: zone.identifier,
                                      knownCities: model.cities + WorldCity.defaults)
            let match = PlaceMatch(
                name: address?.cityName ?? typedCity,
                country: country,
                flag: flag,
                timeZoneID: zone.identifier
            )
            if !matches.contains(match) { matches.append(match) }
            if matches.count == 3 { break }
        }
        return matches.isEmpty ? .notFound : .found(matches)
    }

    private func add() {
        guard let match = chosenMatch else { return }
        var city = WorldCity(name: match.name, country: match.country, flag: match.flag, timeZoneID: match.timeZoneID)
        if let photo, let data = photo.downscaled(maxDimension: 900).jpegData(compressionQuality: 0.85) {
            let file = "\(city.id).jpg"
            if (try? data.write(to: WorldCity.photosDirectory.appending(path: file))) != nil {
                city.photoFile = file
            }
        }
        model.addCity(city)
        onAdded?(city)
        dismiss()
    }
}

extension UIImage {
    /// Shrinks large library photos so card banners stay light on memory and disk.
    nonisolated func downscaled(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        // Render at 1x so `maxDimension` is in pixels, not points.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

#Preview {
    WorldClockView()
        .environment(AppModel.shared)
}

#Preview("Add City") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            AddCitySheet()
                .presentationDetents([.medium])
        }
        .environment(AppModel.shared)
}

#Preview("Editing rows") {
    VStack(spacing: 18) {
        ForEach(Array(WorldCity.defaults.enumerated()), id: \.element.id) { index, city in
            EditableCityRow(city: city, now: .now, index: index, isEditing: true, onDelete: {})
        }
    }
    .padding(20)
    .background(AppBackground())
    .environment(AppModel.shared)
}
