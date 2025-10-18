import UIKit

extension UIImage {
    /// Returns an orientation-normalized copy of the image.
    func normalized() -> UIImage {
        if imageOrientation == .up {
            return self
        }

        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext() ?? self
    }

    /// Crops the image to a centered square.
    func squareCropped() -> UIImage {
        let normalizedImage = normalized()
        guard let cg = normalizedImage.cgImage else { return normalizedImage }

        let width = CGFloat(cg.width)
        let height = CGFloat(cg.height)
        let side = min(width, height)
        let origin = CGPoint(
            x: (width - side) / 2,
            y: (height - side) / 2
        )
        let rect = CGRect(origin: origin, size: CGSize(width: side, height: side)).integral

        guard let cropped = cg.cropping(to: rect) else { return normalizedImage }
        return UIImage(cgImage: cropped, scale: normalizedImage.scale, orientation: .up)
    }

    /// Resizes the image to ensure the longest edge does not exceed `maxDimension`.
    func resized(maxDimension: CGFloat) -> UIImage {
        let normalizedImage = normalized()
        let longestSide = max(normalizedImage.size.width, normalizedImage.size.height)
        guard longestSide > maxDimension else { return normalizedImage }

        let scale = maxDimension / longestSide
        let newSize = CGSize(width: normalizedImage.size.width * scale, height: normalizedImage.size.height * scale)

        UIGraphicsBeginImageContextWithOptions(newSize, false, normalizedImage.scale)
        defer { UIGraphicsEndImageContext() }
        normalizedImage.draw(in: CGRect(origin: .zero, size: newSize))
        return UIGraphicsGetImageFromCurrentImageContext() ?? normalizedImage
    }

    /// Convenience helper that normalizes, crops to square, and optionally resizes the image.
    func squareArtwork(maxDimension: CGFloat = 800) -> UIImage {
        squareCropped().resized(maxDimension: maxDimension)
    }
}
