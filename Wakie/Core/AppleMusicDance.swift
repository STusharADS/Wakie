//
//  AppleMusicDance.swift
//  Wakie
//
//  Plays a song from the person's Apple Music subscription during Shaky-Shaky.
//  Streaming songs are DRM-protected, so they can only be played through MusicKit's
//  player (never saved as an alarm sound).
//

import Foundation
import MusicKit

/// The Apple Music song picked for dancing. Only the catalog ID and labels are stored.
nonisolated struct AppleMusicSong: Codable, Hashable, Sendable {
    let id: String
    let title: String
    let artist: String
}

enum AppleMusicDance {
    /// Starts the song on repeat. Quietly does nothing if access or a subscription is missing.
    static func play(_ pick: AppleMusicSong) async {
        guard MusicAuthorization.currentStatus == .authorized else { return }
        do {
            var request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(pick.id))
            request.limit = 1
            guard let song = try await request.response().items.first else { return }
            let player = ApplicationMusicPlayer.shared
            player.queue = [song]
            player.state.repeatMode = .one
            try await player.play()
        } catch {
            print("Apple Music playback failed: \(error)")
        }
    }

    static func stop() {
        ApplicationMusicPlayer.shared.stop()
    }
}
