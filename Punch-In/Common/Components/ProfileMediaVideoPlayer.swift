import AVKit
import SwiftUI

struct ProfileMediaVideoPlayer: View {
    @EnvironmentObject private var playbackManager: MediaPlaybackManager
    let media: ProfileMediaItem

    var body: some View {
        Group {
            if media.mediaURL != nil {
                MediaPlayerViewController(player: playbackManager.avPlayer)
                    .onAppear { playbackManager.prepare(media: media) }
                    .onChange(of: media.id) { _ in
                        playbackManager.prepare(media: media)
                    }
                    .onChange(of: media.mediaURL) { _ in
                        playbackManager.prepare(media: media)
                    }
            } else {
                Color.black.opacity(0.1)
            }
        }
    }
}

private struct MediaPlayerViewController: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = true
        if #available(iOS 14.2, *) {
            controller.canStartPictureInPictureAutomaticallyFromInline = true
        }
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
    }
}
