import Foundation
import UniformTypeIdentifiers

enum MimeType {
    static func from(utType: UTType) -> String {
        if let mime = utType.preferredMIMEType {
            return mime
        }

        switch utType {
        case .aiff:
            return "audio/aiff"
        case .mpeg4Audio:
            return "audio/mp4"
        case .mp3:
            return "audio/mpeg"
        case .wav:
            return "audio/wav"
        case .movie:
            return "video/quicktime"
        default:
            if utType.identifier == "com.apple.m4a-audio" {
                return "audio/mp4"
            } else if utType.conforms(to: .image) {
                return "image/jpeg"
            } else if utType.conforms(to: .audio) {
                return "audio/mpeg"
            } else if utType.conforms(to: .movie) || utType.conforms(to: .video) {
                return "video/mp4"
            }
            return "application/octet-stream"
        }
    }

    static func fromFileExtension(_ ext: String) -> String? {
        guard let utType = UTType(filenameExtension: ext.lowercased()) else { return nil }
        return from(utType: utType)
    }
}
