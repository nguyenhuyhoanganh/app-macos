import AVFoundation

public enum VideoAsset {
    /// Builds what the player loops: exactly the video track, so audio that runs a
    /// little longer cannot leave a black gap at the loop point. Silent playback
    /// drops the audio track, because a muted player still keeps coreaudiod busy.
    /// `audioURL` supplies a loop's own sound in place of the video's.
    @MainActor
    public static func make(url: URL, audioURL: URL? = nil, withAudio: Bool) async -> AVAsset {
        let asset = AVURLAsset(url: url)
        guard
            let video = try? await asset.loadTracks(withMediaType: .video).first,
            let range = try? await video.load(.timeRange),
            let transform = try? await video.load(.preferredTransform)
        else { return asset }

        let composition = AVMutableComposition()
        guard
            let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
            (try? videoTrack.insertTimeRange(range, of: video, at: .zero)) != nil
        else { return asset }
        videoTrack.preferredTransform = transform

        let audioSource = audioURL.map(AVURLAsset.init(url:)) ?? asset
        if withAudio,
           let audio = try? await audioSource.loadTracks(withMediaType: .audio).first,
           let audioRange = try? await audio.load(.timeRange),
           let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let shared = range.intersection(audioRange)
            try? audioTrack.insertTimeRange(shared, of: audio, at: shared.start - range.start)
        }
        return composition
    }
}
