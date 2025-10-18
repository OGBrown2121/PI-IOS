import SwiftUI

final class ImageCropperProxy: ObservableObject {
    fileprivate weak var container: CropScrollContainer?

    func croppedImage() -> UIImage? {
        container?.croppedImage()
    }
}

private final class CropScrollContainer: UIView, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()

    private let image: UIImage
    private let aspectRatio: CGFloat
    private var didSetInitialZoom = false

    init(image: UIImage, aspectRatio: CGFloat) {
        self.image = image
        self.aspectRatio = aspectRatio
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        clipsToBounds = true

        scrollView.delegate = self
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bounces = true
        scrollView.bouncesZoom = true
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 6
        scrollView.backgroundColor = .clear

        imageView.image = image
        imageView.contentMode = .scaleAspectFit

        scrollView.addSubview(imageView)
        addSubview(scrollView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        updateZoomForCurrentBounds()
        centerImage()
    }

    private func updateZoomForCurrentBounds() {
        guard image.size.width > 0 && image.size.height > 0 else { return }

        imageView.frame = CGRect(origin: .zero, size: image.size)
        scrollView.contentSize = imageView.frame.size

        let boundsSize = scrollView.bounds.size
        guard boundsSize.width > 0, boundsSize.height > 0 else { return }

        let widthScale = boundsSize.width / image.size.width
        let heightScale = boundsSize.height / image.size.height
        let minScale = max(widthScale, heightScale)

        if scrollView.minimumZoomScale != minScale {
            scrollView.minimumZoomScale = minScale
        }
        scrollView.maximumZoomScale = max(minScale * 4, 4)

        if didSetInitialZoom == false || scrollView.zoomScale < minScale {
            scrollView.zoomScale = minScale
            didSetInitialZoom = true
        }

        centerImage()
    }

    private func centerImage() {
        let boundsSize = scrollView.bounds.size
        let imageFrame = imageView.frame

        let horizontalInset: CGFloat
        if imageFrame.size.width < boundsSize.width {
            horizontalInset = (boundsSize.width - imageFrame.size.width) / 2
        } else {
            horizontalInset = 0
        }

        let verticalInset: CGFloat
        if imageFrame.size.height < boundsSize.height {
            verticalInset = (boundsSize.height - imageFrame.size.height) / 2
        } else {
            verticalInset = 0
        }

        scrollView.contentInset = UIEdgeInsets(top: verticalInset, left: horizontalInset, bottom: verticalInset, right: horizontalInset)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
    }

    func croppedImage() -> UIImage? {
        guard scrollView.zoomScale > 0 else { return nil }
        guard imageView.bounds.width > 0, imageView.bounds.height > 0 else { return nil }
        guard let cgImage = image.cgImage else { return nil }

        let zoomScale = scrollView.zoomScale
        let inset = scrollView.contentInset
        let offset = scrollView.contentOffset

        let normalizedX = (offset.x + inset.left) / zoomScale
        let normalizedY = (offset.y + inset.top) / zoomScale
        let normalizedWidth = scrollView.bounds.width / zoomScale
        let normalizedHeight = scrollView.bounds.height / zoomScale

        let scaleX = image.size.width / imageView.bounds.width
        let scaleY = image.size.height / imageView.bounds.height

        var cropRect = CGRect(
            x: normalizedX * scaleX,
            y: normalizedY * scaleY,
            width: normalizedWidth * scaleX,
            height: normalizedHeight * scaleY
        )

        cropRect = cropRect.intersection(CGRect(origin: .zero, size: image.size)).integral
        guard cropRect.width > 0, cropRect.height > 0 else { return nil }

        let pixelScaleX = CGFloat(cgImage.width) / image.size.width
        let pixelScaleY = CGFloat(cgImage.height) / image.size.height

        let pixelRect = CGRect(
            x: cropRect.origin.x * pixelScaleX,
            y: cropRect.origin.y * pixelScaleY,
            width: cropRect.size.width * pixelScaleX,
            height: cropRect.size.height * pixelScaleY
        ).integral

        guard pixelRect.width > 0, pixelRect.height > 0 else { return nil }
        guard let croppedCG = cgImage.cropping(to: pixelRect) else { return nil }

        return UIImage(cgImage: croppedCG, scale: image.scale, orientation: image.imageOrientation)
    }
}

private struct CropScrollView: UIViewRepresentable {
    let image: UIImage
    let aspectRatio: CGFloat
    @ObservedObject var proxy: ImageCropperProxy

    func makeUIView(context: Context) -> CropScrollContainer {
        let container = CropScrollContainer(image: image, aspectRatio: aspectRatio)
        proxy.container = container
        return container
    }

    func updateUIView(_ uiView: CropScrollContainer, context: Context) {
        proxy.container = uiView
    }
}

struct ImageCropperView: View {
    let image: UIImage
    let aspectRatio: CGFloat
    let onCancel: () -> Void
    let onComplete: (UIImage) -> Void

    @StateObject private var proxy = ImageCropperProxy()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                CropScrollView(image: image, aspectRatio: aspectRatio, proxy: proxy)
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                    )
                    .overlay(alignment: .bottom) {
                        LinearGradient(
                            colors: [Color.black.opacity(0.6), Color.clear],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                        .frame(height: 120)
                        .mask(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                        )
                        .allowsHitTesting(false)
                    }
                    .padding(.horizontal, 12)

                Text("Drag to position and pinch to zoom. We’ll crop your artwork to a square.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)

                Spacer()

                HStack(spacing: 16) {
                    Button {
                        onCancel()
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.secondary.opacity(0.15))
                            )
                    }

                    Button {
                        guard let result = proxy.croppedImage() else { return }
                        onComplete(result)
                        dismiss()
                    } label: {
                        Text("Apply")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(LinearGradient(colors: [Theme.primaryGradientStart, Theme.primaryGradientEnd], startPoint: .leading, endPoint: .trailing))
                            )
                            .foregroundStyle(Color.white)
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.vertical, 24)
            .background(Theme.appBackground.ignoresSafeArea())
            .navigationTitle("Crop Artwork")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
