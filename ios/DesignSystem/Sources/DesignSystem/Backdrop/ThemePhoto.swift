import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A photo of the player's own behind the glass, for a theme of theirs.
///
/// It's kept on the phone as a file, dressed once when it's picked
/// (`dress(_:)`): scaled to a TV's width, softened and dimmed, so whatever
/// it shows, text on the glass over it reads — the way a built-in theme's
/// texture is faint enough to read through. The backdrop draws it as it is,
/// under the glow; Increase Contrast and Reduce Transparency set it aside,
/// as they do every texture.
nonisolated public struct ThemePhoto: Hashable, Sendable {
  /// The dressed photo: a JPEG.
  public let url: URL

  public init(url: URL) {
    self.url = url
  }

  /// The longest side a dressed photo keeps: a TV's width, the largest
  /// backdrop it's drawn as.
  static let longestSide = 1920
  /// How far it's softened, as a share of its longest side: enough to turn
  /// detail into light and shade, not so much it's no longer the photo.
  static let softening = 0.012
  /// How bright it may be once dimmed, in linear light: on average, and at
  /// its brightest (after softening). About as bright as the scene themes'
  /// textures get.
  static let averageLight = 0.03
  static let brightestLight = 0.14

  /// The photo at `source` — in any format iOS reads — dressed for the
  /// glass, as a JPEG; nil if it isn't an image. It reads only as much of
  /// the file as a TV-sized copy needs, so a 48-megapixel photo costs no more
  /// memory than any other.
  public static func dress(contentsOf source: URL) -> Data? {
    guard let photo = downsampled(source, to: longestSide) else { return nil }
    let image = CIImage(cgImage: photo)
    let extent = image.extent
    let blur = CIFilter.gaussianBlur()
    blur.inputImage = image.clampedToExtent()
    blur.radius = Float(max(extent.width, extent.height) * softening)
    guard let soft = blur.outputImage?.cropped(to: extent) else { return nil }

    // Dimmed in linear light — CoreImage works in it — by as much as it
    // takes to bring both the average and the brightest down to the marks.
    let context = CIContext()
    let average = light(of: soft, measuredBy: CIFilter.areaAverage(), in: context)
    let brightest = light(of: soft, measuredBy: CIFilter.areaMaximum(), in: context)
    let scale = min(1, averageLight / max(average, 0.0001), brightestLight / max(brightest, 0.0001))
    let dim = CIFilter.colorMatrix()
    dim.inputImage = soft
    dim.rVector = CIVector(x: scale, y: 0, z: 0, w: 0)
    dim.gVector = CIVector(x: 0, y: scale, z: 0, w: 0)
    dim.bVector = CIVector(x: 0, y: 0, z: scale, w: 0)
    guard let dimmed = dim.outputImage,
      let space = CGColorSpace(name: CGColorSpace.sRGB)
    else { return nil }
    return context.jpegRepresentation(
      of: dimmed, colorSpace: space,
      options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.8])
  }

  /// A vivid colour from the photo at `source`, for the theme's accent: the
  /// hue most of its brightest, most saturated parts share. Nil for a photo
  /// with none — a grey one — or for something that isn't a photo.
  public static func suggestedColor(in source: URL) -> UInt32? {
    guard let photo = downsampled(source, to: 32), let pixels = rgba(of: photo) else { return nil }
    // Twelve hues, each weighed by how vivid its pixels are.
    var weights = [Double](repeating: 0, count: 12)
    var sums = [(Double, Double, Double)](repeating: (0, 0, 0), count: 12)
    for pixel in stride(from: 0, to: pixels.count, by: 4) {
      let rgb = RGB.pack(Double(pixels[pixel]) / 255, Double(pixels[pixel + 1]) / 255, Double(pixels[pixel + 2]) / 255)
      let (hue, saturation, brightness) = RGB.hsb(rgb)
      let vivid = saturation * brightness
      guard vivid > 0.2 else { continue }
      let bin = min(11, Int(hue * 12))
      weights[bin] += vivid * vivid
      let (red, green, blue) = RGB.components(rgb)
      sums[bin].0 += red * vivid * vivid
      sums[bin].1 += green * vivid * vivid
      sums[bin].2 += blue * vivid * vivid
    }
    guard let best = weights.indices.max(by: { weights[$0] < weights[$1] }), weights[best] > 0 else { return nil }
    let (red, green, blue) = sums[best]
    let mean = RGB.pack(red / weights[best], green / weights[best], blue / weights[best])
    // As saturated as its pixels, but at full brightness: an accent glows.
    let (hue, saturation, _) = RGB.hsb(mean)
    return RGB.fromHSB(hue, min(saturation, 0.75), 1)
  }

  /// The photo at `url`, upright, no longer on its longest side than `side`.
  private static func downsampled(_ url: URL, to side: Int) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: side,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  }

  /// `image`'s light by `filter` — an average or a maximum — as relative
  /// luminance in linear light.
  private static func light(of image: CIImage, measuredBy filter: some CIAreaReductionFilter, in context: CIContext) -> Double {
    filter.inputImage = image
    filter.extent = image.extent
    guard let output = filter.outputImage else { return 0 }
    var pixel = [Float](repeating: 0, count: 4)
    context.render(
      output, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
      format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB))
    return 0.2126 * Double(pixel[0]) + 0.7152 * Double(pixel[1]) + 0.0722 * Double(pixel[2])
  }

  /// `image`'s pixels as sRGB bytes, four to a pixel.
  private static func rgba(of image: CGImage) -> [UInt8]? {
    let (width, height) = (image.width, image.height)
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return pixels
  }
}

#if DEBUG
extension ThemePhoto {
  /// A bright photo, dressed: a midday sky of white cloud over pale sand —
  /// the hardest kind for text to read over. For fixtures and the contrast
  /// test (`-theme photo`).
  public static func brightSample() -> ThemePhoto? {
    let url = URL.temporaryDirectory.appending(path: "BrightSample.jpg")
    if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) { return ThemePhoto(url: url) }
    let size = CGSize(width: 1200, height: 1600)
    let photo = UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.9) { context in
      let colors = [UIColor(red: 0.55, green: 0.8, blue: 1, alpha: 1), UIColor(white: 0.98, alpha: 1), UIColor(red: 0.96, green: 0.9, blue: 0.75, alpha: 1)]
      let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors.map(\.cgColor) as CFArray, locations: [0, 0.55, 1])!
      context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
      UIColor.white.setFill()
      for cloud in 0..<9 {
        let x = CGFloat(cloud % 3) * 420 - 60, y = CGFloat(cloud / 3) * 330 + 80
        UIBezierPath(ovalIn: CGRect(x: x, y: y, width: 520, height: 220)).fill()
      }
    }
    let source = URL.temporaryDirectory.appending(path: "BrightSample-source.jpg")
    guard (try? photo.write(to: source)) != nil, let dressed = dress(contentsOf: source), (try? dressed.write(to: url)) != nil else { return nil }
    return ThemePhoto(url: url)
  }
}
#endif

/// Dressed photos, decoded once and kept while they're in use: at full size
/// for a backdrop, and small for a swatch or a bubble — a page of bubbles
/// shouldn't hold a TV's worth of pixels for each.
@MainActor @Observable
final class ThemePhotos {
  static let shared = ThemePhotos()

  enum Fit: Hashable {
    case screen
    case miniature

    /// The longest side it's decoded at, in pixels.
    var side: Int? {
      switch self {
      case .screen: nil
      case .miniature: 360
      }
    }
  }

  private struct Key: Hashable {
    let url: URL
    let fit: Fit
  }

  private var images: [Key: UIImage] = [:]
  @ObservationIgnored private var loading: Set<Key> = []

  /// The photo, if it's decoded yet. If it isn't, it's decoded off the main
  /// actor, and whatever asked is drawn again when it is.
  func image(for photo: ThemePhoto, fit: Fit) -> UIImage? {
    let key = Key(url: photo.url, fit: fit)
    if let image = images[key] { return image }
    if !loading.contains(key) {
      loading.insert(key)
      Task {
        let (url, side) = (photo.url, fit.side)
        let image = await Task.detached(priority: .userInitiated) { Self.decode(url, side: side) }.value
        // Only news is written: a photo that won't decode, written as nil,
        // would redraw what asked, which would ask again, for good.
        if let image { images[key] = image }
        loading.remove(key)
      }
    }
    return nil
  }

  /// Lets go of a photo that's gone, so a new one at the same place is read
  /// afresh.
  func forget(_ photo: ThemePhoto) {
    for key in images.keys where key.url == photo.url {
      images[key] = nil
    }
  }

  nonisolated private static func decode(_ url: URL, side: Int?) -> UIImage? {
    guard let side else { return UIImage(contentsOfFile: url.path(percentEncoded: false))?.preparingForDisplay() }
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: side,
        ] as CFDictionary)
    else { return nil }
    return UIImage(cgImage: image)
  }
}

extension ThemePhoto {
  /// Forgets the decoded copies of this photo: call it when the file goes.
  @MainActor public func forget() {
    ThemePhotos.shared.forget(self)
  }
}

/// A theme's photo, filling the backdrop.
struct PhotoGround: View {
  let photo: ThemePhoto
  @Environment(\.backdropIsMiniature) private var isMiniature

  var body: some View {
    let image = ThemePhotos.shared.image(for: photo, fit: isMiniature ? .miniature : .screen)
    Color.clear
      .overlay {
        if let image {
          Image(uiImage: image)
            .resizable()
            .scaledToFill()
        }
      }
      .clipped()
      // Fades in once it's decoded, rather than popping over the ink.
      .motion(.settle, value: image != nil)
  }
}

nonisolated extension EnvironmentValues {
  /// Whether a backdrop is a swatch's or a bubble's: a photo is then decoded
  /// small.
  @Entry public var backdropIsMiniature = false
}
