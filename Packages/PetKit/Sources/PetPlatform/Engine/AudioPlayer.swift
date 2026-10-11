import AVFoundation
import PetCore

/// Small pool of preloaded players, keyed by file. Sounds are short one-shots; nothing streams.
@MainActor
final class AudioPlayer {
    private var players: [URL: AVAudioPlayer] = [:]

    func play(_ name: String, pack: LoadedPack, volume: Double) {
        guard let file = pack.data.definition.sounds[name] else { return }
        let url = pack.data.directory.appending(path: file)
        let player: AVAudioPlayer
        if let p = players[url] {
            player = p
        } else {
            guard let p = try? AVAudioPlayer(contentsOf: url) else {
                log.error("cannot play sound \(url.lastPathComponent, privacy: .public)")
                return
            }
            p.prepareToPlay()
            players[url] = p
            player = p
        }
        player.volume = Float(min(max(volume, 0), 1))
        player.currentTime = 0
        player.play()
    }

    /// Frees decoded audio between appearances.
    func purge() { players.removeAll() }
}
