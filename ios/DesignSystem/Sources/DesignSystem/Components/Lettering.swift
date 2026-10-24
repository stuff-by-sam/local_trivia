import CoreText
import SwiftUI
import Synchronization
import UIKit
import Vision

/// A line of text set as outlines, so it can be made of real Liquid Glass:
/// the system's glass takes a shape, and this makes the text one.
/// (`SymbolOutlines`, below, does the same for SF Symbols.)
///
/// Also says where a terminal's block cursor goes after it: the next
/// character cell, as tall as a capital and standing on the baseline, so the
/// block lines up with the letters' tops and feet.
nonisolated struct Lettering: Sendable {
  /// The glyphs' outlines, in a box `box` with its origin at the top left.
  let letters: Path
  /// The line as SwiftUI lays it out: every character's advance and tracking,
  /// the last one's too, by the font's line height.
  let box: CGSize
  /// The word: its characters' cells, less the tracking after the last.
  let size: CGSize
  /// The block cursor in the cell after the word, in the same box — past its
  /// trailing edge, so the word itself is what's centred.
  let cursor: CGRect

  /// `text` in the system's mono face: the wordmark.
  init(_ text: String, size pointSize: CGFloat, weight: UIFont.Weight, tracking: CGFloat) {
    self.init(text, font: UIFont.monospacedSystemFont(ofSize: pointSize, weight: weight) as CTFont, tracking: tracking)
  }

  /// `text` in `font` — a font SwiftUI resolved (`Font.Resolved.ctFont`), so
  /// the outlines are the letters it draws.
  init(_ text: String, font: CTFont, tracking: CGFloat) {
    let ascent = CTFontGetAscent(font)
    let descent = CTFontGetDescent(font)
    let line = CTLineCreateWithAttributedString(
      NSAttributedString(string: text, attributes: [.font: font, .kern: tracking])
    )

    var letters = Path()
    for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
      // A run's own font: a character the face hasn't got falls back to another.
      let attributes = CTRunGetAttributes(run) as? [NSAttributedString.Key: Any]
      let runFont = attributes?[.font].map { $0 as! CTFont } ?? font
      let count = CTRunGetGlyphCount(run)
      var glyphs = [CGGlyph](repeating: 0, count: count)
      var positions = [CGPoint](repeating: .zero, count: count)
      CTRunGetGlyphs(run, CFRange(), &glyphs)
      CTRunGetPositions(run, CFRange(), &positions)
      for (glyph, position) in zip(glyphs, positions) {
        guard let outline = CTFontCreatePathForGlyph(runFont, glyph, nil) else { continue }
        // Core Text draws up from the baseline; SwiftUI draws down from the top.
        let place = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: position.x, ty: ascent - position.y)
        letters.addPath(Path(outline), transform: place)
      }
    }
    self.letters = letters

    // Kerning follows every character, the last one too: that's the cells'
    // width, as SwiftUI lays the line out, and the word's is one tracking less.
    let cells = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    self.box = CGSize(width: cells, height: ascent + descent)
    self.size = CGSize(width: cells - tracking, height: ascent + descent)

    // A capital's ink, for the block: an H is as tall as the caps and as wide
    // as a heavy letter's stems allow.
    var capital: [CGGlyph] = [0]
    var ink = CGRect.zero
    CTFontGetGlyphsForCharacters(font, Array("H".utf16), &capital, 1)
    CTFontGetBoundingRectsForGlyphs(font, .horizontal, capital, &ink, 1)
    self.cursor = CGRect(x: cells + ink.minX, y: ascent - ink.maxY, width: ink.width, height: ink.height)
  }
}

/// A path as a shape, drawn where it was set.
nonisolated struct OutlineShape: Shape {
  let path: Path

  func path(in rect: CGRect) -> Path {
    path
  }
}

/// The outline of an SF Symbol, so it can be made of real Liquid Glass.
///
/// The system has no API for a symbol's paths, so this traces the system's own
/// symbol: draws it, large, and has Vision find its contours. Nothing of the
/// symbol ships in the app. A trace takes a few milliseconds, off the main
/// actor, and happens once: the app traces every symbol it will make of glass
/// at launch (`prepare(_:)`), and keeps them on the device, so a later launch
/// draws glass from its first frame.
nonisolated enum SymbolOutlines {
  private static let traced = Mutex<[String: Path]>(Saved.load())
  /// Traces under way, so two glyphs that ask at once share one.
  private static let tracing = Mutex<[String: Task<Path?, Never>]>([:])

  /// `name`'s outline in a unit square, y down, if it's been traced.
  static func cached(_ name: String) -> Path? {
    traced.withLock { $0[name] }
  }

  /// `name`'s outline in a unit square, y down: from the cache, or traced now.
  static func outline(_ name: String) async -> Path? {
    if let path = cached(name) { return path }
    let task = tracing.withLock { tasks in
      if let task = tasks[name] { return task }
      let task = Task.detached(priority: .userInitiated) { trace(name) }
      tasks[name] = task
      return task
    }
    let path = await task.value
    tracing.withLock { $0[name] = nil }
    if let path {
      // Saved under the lock, so two traces finishing together can't save
      // an older set over a newer one.
      traced.withLock { all in
        all[name] = path
        Saved.store(all)
      }
    }
    return path
  }

  /// Traces `names` that aren't yet, one after another.
  static func prepare(_ names: [String]) async {
    for name in names where cached(name) == nil {
      _ = await outline(name)
    }
  }

  private static func trace(_ name: String) -> Path? {
    // Large enough that the contours' pixel steps vanish at any size it's drawn.
    let configuration = UIImage.SymbolConfiguration(pointSize: 200, weight: .semibold)
    guard let symbol = Symbols.uiImage(name, configuration: configuration) else { return nil }
    let size = symbol.size
    // Whole pixels, all of them white: a part-pixel edge left unfilled reads
    // as a dark sliver, and Vision would trace it.
    let canvas = CGRect(x: 0, y: 0, width: size.width.rounded(.up), height: size.height.rounded(.up))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let image = UIGraphicsImageRenderer(bounds: canvas, format: format).image { context in
      UIColor.white.setFill()
      context.fill(canvas)
      symbol.withTintColor(.black, renderingMode: .alwaysOriginal).draw(in: CGRect(origin: .zero, size: size))
    }
    guard let cgImage = image.cgImage else { return nil }

    let request = VNDetectContoursRequest()
    request.detectsDarkOnLight = true
    request.maximumImageDimension = Int(max(canvas.width, canvas.height))
    try? VNImageRequestHandler(cgImage: cgImage).perform([request])
    guard let contours = request.results?.first else { return nil }

    // The shape, and the holes in it: each contour big enough to be part of
    // the symbol, with its children. A speck of antialiasing isn't. Each is
    // smoothed of its pixel steps — a fraction of a point at any size it's
    // drawn — which also leaves the glass far fewer points to bend.
    let outline = CGMutablePath()
    func add(_ contour: VNContour) {
      let box = contour.normalizedPath.boundingBox
      guard box.width * box.height > 0.0004 else { return }
      let smooth = (try? contour.polygonApproximation(epsilon: 0.0025)) ?? contour
      outline.addPath(smooth.normalizedPath)
      contour.childContours.forEach(add)
    }
    contours.topLevelContours.forEach(add)

    // From Vision's square of the canvas, y up, to a unit square of the
    // symbol, y down. Even-odd, so a hole — an eye, a shell's plates — stays a
    // hole under the glass's winding fill.
    var place = CGAffineTransform(a: canvas.width / size.width, b: 0, c: 0, d: -canvas.height / size.height, tx: 0, ty: canvas.height / size.height)
    guard let placed = outline.copy(using: &place) else { return nil }
    return Path(placed.normalized(using: .evenOdd))
  }

  /// The traces kept on the device between launches: in Caches, so the
  /// system may clear them; per OS build, whose symbols may differ, and per
  /// app build, whose own symbols (`Symbols.custom`) may.
  private enum Saved {
    static var url: URL? {
      let build = ProcessInfo.processInfo.operatingSystemVersionString.filter { $0.isLetter || $0.isNumber }
      let app = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "").filter { $0.isLetter || $0.isNumber }
      return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appending(path: "GlassOutlines-2-\(build)-\(app).plist")
    }

    static func load() -> [String: Path] {
      guard let url, let data = try? Data(contentsOf: url),
        let saved = try? PropertyListDecoder().decode([String: String].self, from: data)
      else { return [:] }
      return saved.compactMapValues(Path.init)
    }

    static func store(_ outlines: [String: Path]) {
      guard let url, let data = try? PropertyListEncoder().encode(outlines.mapValues(\.description)) else { return }
      try? data.write(to: url, options: .atomic)
    }
  }
}

/// An outline in a unit square, stretched over the frame it's given, less
/// `inset` all round.
nonisolated struct UnitOutlineShape: Shape {
  let path: Path
  var inset: CGFloat = 0

  func path(in rect: CGRect) -> Path {
    let rect = rect.insetBy(dx: inset, dy: inset)
    return path.applying(CGAffineTransform(a: rect.width, b: 0, c: 0, d: rect.height, tx: rect.minX, ty: rect.minY))
  }
}

/// An outline set in a box, scaled evenly to fit the frame it's given and
/// centred in it — so lettering follows its text when SwiftUI shrinks it to
/// fit (`minimumScaleFactor`).
nonisolated struct FittedOutline: Shape {
  let path: Path
  let box: CGSize

  func path(in rect: CGRect) -> Path {
    guard box.width > 0, box.height > 0 else { return Path() }
    let scale = min(rect.width / box.width, rect.height / box.height)
    let x = rect.midX - box.width * scale / 2
    let y = rect.midY - box.height * scale / 2
    return path.applying(CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: x, ty: y))
  }
}

/// A shape, drawn `inset` in from every side of the frame it's given.
nonisolated struct InsetShape<Base: Shape>: Shape {
  let base: Base
  let inset: CGFloat

  func path(in rect: CGRect) -> Path {
    base.path(in: rect.insetBy(dx: inset, dy: inset))
  }
}
