import SwiftUI
import AVFoundation

struct LoopingVideoView: UIViewRepresentable {
    let url: URL?
    var isMuted: Bool = true
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill

    func makeUIView(context: Context) -> LoopingPlayerView {
        let view = LoopingPlayerView()
        view.configure(with: url, isMuted: isMuted, videoGravity: videoGravity)
        return view
    }

    func updateUIView(_ uiView: LoopingPlayerView, context: Context) {
        uiView.configure(with: url, isMuted: isMuted, videoGravity: videoGravity)
    }
}

final class LoopingPlayerView: UIView {
    private let queuePlayer = AVQueuePlayer()
    private var looper: AVPlayerLooper?

    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        playerLayer.player = queuePlayer
        playerLayer.videoGravity = .resizeAspectFill
        queuePlayer.actionAtItemEnd = .none
    }

    func configure(with url: URL?, isMuted: Bool, videoGravity: AVLayerVideoGravity) {
        playerLayer.videoGravity = videoGravity
        queuePlayer.isMuted = isMuted

        guard let url else {
            queuePlayer.pause()
            looper?.disableLooping()
            looper = nil
            queuePlayer.removeAllItems()
            return
        }

        if let currentAsset = (queuePlayer.currentItem?.asset as? AVURLAsset), currentAsset.url == url {
            if queuePlayer.timeControlStatus != .playing {
                queuePlayer.play()
            }
            return
        }

        looper?.disableLooping()
        looper = nil
        queuePlayer.removeAllItems()

        let item = AVPlayerItem(url: url)
        // Keep a strong reference to the looper so the item repeats smoothly.
        looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        queuePlayer.play()
    }
}
