//
//  SoundPickerSheet.swift
//  Wakie
//
//  Choose the alarm sound: Wakie's own built-in tones or songs imported from Files.
//

import SwiftUI
import UniformTypeIdentifiers

struct SoundPickerSheet: View {
    @Binding var selection: String?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var player = AudioPreviewPlayer()
    @State private var isImporting = false
    @State private var isConverting = false
    @State private var importError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Ringtone")
                    .font(.wakie(22, .heavy))
                    .foregroundStyle(Theme.ink)
                Spacer()
                CircleIconButton(systemName: "xmark", size: 40) { dismiss() }
                    .accessibilityLabel("Done")
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 10) {
                    sectionLabel("Wakie sounds")
                    ForEach(ToneLibrary.alarmTones) { tone in
                        // The default tone is stored as "no pick", so it follows future default changes.
                        row(title: tone.title, subtitle: tone.subtitle,
                            file: tone.file == ToneLibrary.defaultAlarmFile ? nil : tone.file,
                            previewFile: tone.file)
                    }
                    if !model.alarmSounds.isEmpty { sectionLabel("Your songs") }
                    ForEach(model.alarmSounds, id: \.self) { file in
                        row(title: AudioImporter.title(forFile: file), subtitle: "From your files", file: file)
                    }
                    addButton
                    Text("Ringtones use the first 29 seconds of the song.")
                        .font(.wakie(12, .semibold))
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
        }
        .background(AppBackground(showsBlobs: false))
        .presentationDragIndicator(.visible)
        .onDisappear { player.stop() }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.audio]) { result in
            guard case let .success(url) = result else { return }
            isConverting = true
            Task {
                do {
                    selection = try await model.importAlarmSound(from: url)
                } catch {
                    importError = "That song couldn't be turned into an alarm sound. Try a different file."
                }
                isConverting = false
            }
        }
        .alert("Couldn't add sound", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.wakie(13, .heavy))
            .foregroundStyle(Theme.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
    }

    private func row(title: String, subtitle: String, file: String?, previewFile: String? = nil) -> some View {
        let isSelected = selection == file
        let url = (previewFile ?? file).map { AudioImporter.alarmSoundsDirectory.appending(path: $0) }
        return HStack(spacing: 12) {
            if let url {
                Button {
                    player.toggle(url)
                } label: {
                    Image(systemName: player.playingURL == url ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(Color(hex: 0x1E1A3C))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Theme.yellow))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.playingURL == url ? "Stop preview" : "Preview \(title)")
            } else {
                Image(systemName: "bell.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.purple)
                    .frame(width: 34, height: 34)
            }
            Button {
                selection = file
                // Preview what was just picked, so people hear their choice.
                if let url, player.playingURL != url { player.toggle(url) }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title)
                            .font(.wakie(15, .bold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.wakie(12, .semibold))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.purple)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            if let file, !ToneLibrary.isBuiltIn(file) {
                Button {
                    if player.playingURL == url { player.stop() }
                    if selection == file { selection = nil }
                    withAnimation(.snappy) { model.deleteAlarmSound(file) }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.danger)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete \(title)")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
        .sensoryFeedback(.selection, trigger: isSelected)
        .wakieCard(radius: 18)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.purple, lineWidth: isSelected ? 2 : 0)
        )
    }

    private var addButton: some View {
        Button {
            isImporting = true
        } label: {
            HStack(spacing: 10) {
                if isConverting {
                    ProgressView()
                    Text("Adding song…")
                } else {
                    Image(systemName: "plus.circle.fill")
                    Text("Add a song from Files")
                }
            }
            .font(.wakie(15, .bold))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Capsule().fill(Theme.lavenderPill))
        }
        .buttonStyle(PressableStyle())
        .disabled(isConverting)
    }
}
