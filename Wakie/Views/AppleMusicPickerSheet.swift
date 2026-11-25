//
//  AppleMusicPickerSheet.swift
//  Wakie
//
//  Connect Apple Music and search the catalog for a song to dance to in Shaky-Shaky.
//

import MusicKit
import SwiftUI

struct AppleMusicPickerSheet: View {
    let onPick: (AppleMusicSong) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var status = MusicAuthorization.currentStatus
    @State private var canPlay = true
    @State private var term = ""
    @State private var songs: [Song] = []
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            Group {
                switch status {
                case .authorized:
                    results
                case .denied, .restricted:
                    message(title: "Apple Music is off for Wakie",
                            detail: "Allow Media & Apple Music for Wakie in Settings to pick a song.",
                            buttonTitle: "Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                default:
                    message(title: "Dance to your Apple Music",
                            detail: "Connect your Apple Music subscription to play any song while you dance.",
                            buttonTitle: "Connect Apple Music") {
                        Task { status = await MusicAuthorization.request() }
                    }
                }
            }
            .navigationTitle("Apple Music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task(id: status) {
            guard status == .authorized else { return }
            // Catalog songs only play with an active subscription.
            canPlay = (try? await MusicSubscription.current.canPlayCatalogContent) ?? false
        }
    }

    private var results: some View {
        List {
            if !canPlay {
                Label("An Apple Music subscription is needed to play songs.", systemImage: "exclamationmark.triangle.fill")
                    .font(.wakie(13, .semibold))
                    .foregroundStyle(Theme.danger)
            }
            ForEach(songs) { song in
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    onPick(AppleMusicSong(id: song.id.rawValue, title: song.title, artist: song.artistName))
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        if let artwork = song.artwork {
                            ArtworkImage(artwork, width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        } else {
                            Image(systemName: "music.note")
                                .frame(width: 48, height: 48)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.lavenderPill))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title)
                                .font(.wakie(15, .bold))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            Text(song.artistName)
                                .font(.wakie(13, .semibold))
                                .foregroundStyle(Theme.inkSecondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .overlay {
            if isSearching {
                ProgressView()
            } else if songs.isEmpty {
                ContentUnavailableView(term.isEmpty ? "Search for a song" : "No songs found",
                                       systemImage: "music.magnifyingglass",
                                       description: Text(term.isEmpty ? "Try an upbeat song to get you moving." : "Try a different search."))
            }
        }
        .searchable(text: $term, placement: .navigationBarDrawer(displayMode: .always), prompt: "Songs or artists")
        .task(id: term) {
            // Wait for typing to pause before searching.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    private func search() async {
        let query = term.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            songs = []
            return
        }
        isSearching = true
        defer { isSearching = false }
        var request = MusicCatalogSearchRequest(term: query, types: [Song.self])
        request.limit = 25
        songs = (try? await request.response().songs.map { $0 }) ?? []
    }

    private func message(title: String, detail: String, buttonTitle: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note.house.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.purple)
            Text(title)
                .font(.wakie(20, .black))
                .foregroundStyle(Theme.ink)
            Text(detail)
                .font(.wakie(14, .semibold))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
            Button(action: action) {
                Text(buttonTitle)
                    .font(.wakie(16, .heavy))
                    .foregroundStyle(Color(hex: 0x1E1A3C))
                    .padding(.horizontal, 24)
                    .frame(height: 50)
                    .background(Capsule().fill(Theme.yellow))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
