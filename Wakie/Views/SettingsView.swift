//
//  SettingsView.swift
//  Wakie
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var player = AudioPreviewPlayer()
    @State private var isPickingSong = false
    @State private var isImportingSong = false
    @State private var importError: String?

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    ScreenTitle(text: "Settings")
                    Spacer()
                }
                shakySection(seconds: $model.danceSeconds)
                blahSection(seconds: $model.talkSeconds)
                pickieSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .onAppear { model.refreshRecordings() }
        .onDisappear { player.stop() }
        .fileImporter(isPresented: $isPickingSong, allowedContentTypes: [.audio]) { result in
            guard case let .success(url) = result else { return }
            player.stop()
            isImportingSong = true
            Task {
                do {
                    try await model.importDanceSong(from: url)
                } catch {
                    importError = "That song couldn't be added. Try a different file."
                }
                isImportingSong = false
            }
        }
        .alert("Couldn't add song", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    // MARK: Shaky-Shaky

    private func shakySection(seconds: Binding<Int>) -> some View {
        MissionSettingsCard(mission: .shakyShaky) {
            VStack(alignment: .leading, spacing: 14) {
                DurationSlider(title: "Dance time", seconds: seconds, range: AppModel.missionSecondsRange)
                danceMusicRow
            }
        }
    }

    /// The song that plays while dancing, picked from the Files app.
    private var danceMusicRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dance music")
                .font(.wakie(15, .bold))
                .foregroundStyle(Theme.ink)
            HStack(spacing: 12) {
                if let url = model.danceSongURL, let file = model.danceSongFile {
                    Button {
                        player.toggle(url)
                    } label: {
                        Image(systemName: player.playingURL == url ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(Color(hex: 0x1E1A3C))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Theme.yellow))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(player.playingURL == url ? "Pause song" : "Play song")
                    Text(AudioImporter.title(forFile: file))
                        .font(.wakie(14, .bold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button {
                        player.stop()
                        withAnimation(.snappy) { model.removeDanceSong() }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.danger)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove song")
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.purple)
                        .frame(width: 36, height: 36)
                    Text("No song. Dance to your own beat!")
                        .font(.wakie(13, .semibold))
                        .foregroundStyle(Theme.inkSecondary)
                    Spacer(minLength: 4)
                }
                Button {
                    isPickingSong = true
                } label: {
                    if isImportingSong {
                        ProgressView()
                    } else {
                        Text(model.danceSongFile == nil ? "Choose" : "Change")
                            .font(.wakie(13, .bold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .contentShape(Capsule())
                    }
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(Theme.purple.opacity(0.25)).interactive(), in: .capsule)
                .disabled(isImportingSong)
            }
            .padding(.horizontal, 12)
            .frame(height: 54)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.inset))
        }
    }

    // MARK: Pickie-Picky

    private var pickieSection: some View {
        MissionSettingsCard(mission: .pickiePicky) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Items to find")
                    .font(.wakie(15, .bold))
                    .foregroundStyle(Theme.ink)
                ForEach(model.pickItems) { item in
                    pickItemRow(item, isActive: true)
                }
                if model.pickItems.count <= 1 {
                    Text("Keep at least one item so there's always something to find.")
                        .font(.wakie(12, .semibold))
                        .foregroundStyle(Theme.inkSecondary)
                }
                // Removed items stay visible, greyed out at the bottom, each with its own restore button.
                if !model.removedPickItems.isEmpty {
                    Text("Removed")
                        .font(.wakie(13, .bold))
                        .foregroundStyle(Theme.inkSecondary)
                        .padding(.top, 6)
                    ForEach(model.removedPickItems) { item in
                        pickItemRow(item, isActive: false)
                    }
                    if model.removedPickItems.count > 1 {
                        Button {
                            withAnimation(.snappy) { model.restorePickItems() }
                        } label: {
                            Label("Restore all items", systemImage: "arrow.counterclockwise")
                                .font(.wakie(14, .bold))
                                .foregroundStyle(Theme.purple)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }
            }
        }
    }

    /// One item row. Active rows can be removed; removed rows are greyed and can be restored.
    private func pickItemRow(_ item: PickItem, isActive: Bool) -> some View {
        let canRemove = model.pickItems.count > 1
        return HStack(spacing: 12) {
            Text(item.emoji)
                .font(.system(size: 22))
                .grayscale(isActive ? 0 : 1)
            Text(item.name)
                .font(.wakie(16, .semibold))
                .foregroundStyle(isActive ? Theme.ink : Theme.inkSecondary)
                .strikethrough(!isActive, color: Theme.inkSecondary)
            Spacer()
            Button {
                withAnimation(.snappy) {
                    if isActive { model.removePickItem(item) } else { model.restorePickItem(item) }
                }
            } label: {
                Image(systemName: isActive ? "minus.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(isActive
                                     ? (canRemove ? Theme.danger : Theme.inkSecondary.opacity(0.4))
                                     : Color.green)
            }
            .buttonStyle(.plain)
            .disabled(isActive && !canRemove)
            .accessibilityLabel(isActive ? "Remove \(item.name)" : "Restore \(item.name)")
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.inset))
        .opacity(isActive ? 1 : 0.55)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: Blah-Blah

    private func blahSection(seconds: Binding<Int>) -> some View {
        MissionSettingsCard(mission: .blahBlah) {
            VStack(alignment: .leading, spacing: 14) {
                DurationSlider(title: "Talk time", seconds: seconds, range: AppModel.missionSecondsRange)
                Text("Recordings")
                    .font(.wakie(15, .bold))
                    .foregroundStyle(Theme.ink)
                if model.recordings.isEmpty {
                    Text("Your morning rambles will show up here.")
                        .font(.wakie(13, .semibold))
                        .foregroundStyle(Theme.inkSecondary)
                } else {
                    ForEach(model.recordings) { recording in
                        RecordingRow(
                            recording: recording,
                            isPlaying: player.playingURL == recording.url,
                            onPlay: { player.toggle(recording.url) },
                            onDelete: {
                                if player.playingURL == recording.url { player.stop() }
                                withAnimation(.snappy) { model.deleteRecording(recording) }
                            }
                        )
                    }
                }
            }
        }
    }
}

/// Card with a mission header used for each settings section.
struct MissionSettingsCard<Content: View>: View {
    let mission: Mission
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                MascotImage(mission: mission, size: 50)
                Text(mission.title)
                    .font(.wakie(22, .black))
                    .foregroundStyle(Color(hex: 0x1E1A3C))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .background(BrushBanner().fill(mission.bannerColor))
                Spacer()
            }
            content
        }
        .padding(18)
        .wakieCard(radius: 28)
    }
}

struct DurationSlider: View {
    let title: String
    @Binding var seconds: Int
    let range: ClosedRange<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.wakie(15, .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("\(seconds)s")
                    .font(.wakie(15, .heavy))
                    .foregroundStyle(Theme.purple)
                    .contentTransition(.numericText())
            }
            Slider(
                value: Binding(get: { Double(seconds) }, set: { seconds = Int($0.rounded()) }),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 5
            ) {
                Text(title)
            } minimumValueLabel: {
                Text("\(range.lowerBound)s").font(.wakie(11, .semibold)).foregroundStyle(Theme.inkSecondary)
            } maximumValueLabel: {
                Text("\(range.upperBound)s").font(.wakie(11, .semibold)).foregroundStyle(Theme.inkSecondary)
            }
            .tint(Theme.purple)
        }
    }
}

struct RecordingRow: View {
    let recording: VoiceRecording
    let isPlaying: Bool
    let onPlay: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(Color(hex: 0x1E1A3C))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.yellow))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            VStack(alignment: .leading, spacing: 0) {
                Text(recording.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.wakie(14, .bold))
                    .foregroundStyle(Theme.ink)
                Text(recording.durationText)
                    .font(.wakie(12, .semibold))
                    .foregroundStyle(Theme.inkSecondary)
            }
            Spacer()
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.danger)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete recording")
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.inset))
    }
}

#Preview {
    SettingsView()
        .environment(AppModel.shared)
}

#Preview("Some items removed") {
    let model = AppModel.shared
    model.pickItems = PickItem.defaults.filter { !["Fork", "Book"].contains($0.name) }
    return SettingsView()
        .environment(model)
}
