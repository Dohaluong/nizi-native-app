import CoreLocation
import CryptoKit
import Foundation
import ImageIO
import Photos

enum NiziMovePhotoSaver {
    static func sha256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_024 * 1_024) ?? Data()
            guard !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Uses the manifest date when available, then the image's embedded EXIF/TIFF date.  Photos
    /// does not reliably promote embedded metadata to `PHAsset.creationDate` after an import, so
    /// assigning this explicitly is essential for downstream event/trip indexing.
    static func save(
        fileURL: URL,
        metadata: NiziMoveManifestAsset,
        preferredCreationDate: Date? = nil
    ) async throws -> String {
        let creationDate = preferredCreationDate ?? metadata.capturedAt ?? embeddedCaptureDate(in: fileURL)
        try await withCheckedThrowingContinuation { continuation in
            var identifier: String?
            PHPhotoLibrary.shared().performChanges {
                guard let request = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL) else { return }
                request.creationDate = creationDate
                if let latitude = metadata.latitude, let longitude = metadata.longitude { request.location = CLLocation(latitude: latitude, longitude: longitude) }
                identifier = request.placeholderForCreatedAsset?.localIdentifier
            } completionHandler: { success, error in
                if success, let identifier { continuation.resume(returning: identifier) }
                else { continuation.resume(throwing: error ?? NiziMoveError.server("PHOTO_SAVE_FAILED")) }
            }
        }
    }

    /// Reads the two widely-used capture-date fields without exposing raw EXIF to the rest of the
    /// import flow.  The EXIF value takes precedence over TIFF, which often only reflects export
    /// time.  EXIF dates without an offset are deliberately interpreted in the device's current
    /// time zone, the same convention Photos uses for those legacy files.
    static func embeddedCaptureDate(in fileURL: URL) -> Date? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let dateString = exif?[kCGImagePropertyExifDateTimeOriginal] as? String
            ?? exif?[kCGImagePropertyExifDateTimeDigitized] as? String
            ?? tiff?[kCGImagePropertyTIFFDateTime] as? String
        guard let dateString else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: dateString)
    }
}
