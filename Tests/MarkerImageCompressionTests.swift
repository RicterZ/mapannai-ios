import XCTest
import UIKit
@testable import MapAnNai

final class MarkerImageCompressionTests: XCTestCase {
    func testLargePhotoIsDownsampledTo1600Pixels() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3200, height: 2400), format: format).image { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 3200, height: 2400))
        }
        let source = try XCTUnwrap(image.pngData())
        let jpeg = try MarkerImageCompression.jpeg(from: source)
        let result = try XCTUnwrap(UIImage(data: jpeg)?.cgImage)
        XCTAssertEqual(result.width, 1600)
        XCTAssertEqual(result.height, 1200)
        XCTAssertEqual(Array(jpeg.prefix(2)), [0xff, 0xd8])
    }
    func testSmallPhotoKeepsDimensionsAndInvalidDataIsRejected() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 320), format: format).image { _ in }
        let jpeg = try MarkerImageCompression.jpeg(from: XCTUnwrap(image.pngData()))
        let result = try XCTUnwrap(UIImage(data: jpeg)?.cgImage)
        XCTAssertEqual(result.width, 240)
        XCTAssertEqual(result.height, 320)
        XCTAssertThrowsError(try MarkerImageCompression.jpeg(from: Data("bad image".utf8)))
    }
}
