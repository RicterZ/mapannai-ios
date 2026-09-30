import Foundation
import ImageIO
import UIKit

enum MarkerImageCompression {
    static func jpeg(from bytes: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw AppError.message("无法读取图片") }
        guard let data = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.82) else {
            throw AppError.message("无法编码图片")
        }
        return data
    }
}
