import Foundation

/// The web player, for phones without the app: the laptop server's own player
/// page (`public/play`), bundled into the app at build time and served by
/// `HostServer` on the game's port. The join link in the host's QR code opens
/// it, so any phone's camera can join; the page talks to the game over the
/// same WebSocket the app uses.
///
/// Only the files bundled under `Web/` are served — looked up by exact path in
/// a list made from the bundle, never by joining the request's path onto a
/// directory — and only to GET and HEAD.
nonisolated struct WebPlayer: Sendable {
  /// Published path → file. "/" is the player page.
  let files: [String: URL]

  static let shared = WebPlayer(root: Bundle.main.url(forResource: "Web", withExtension: nil))

  init(root: URL?) {
    var files: [String: URL] = [:]
    if let root, let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) {
      let base = root.standardizedFileURL.path
      for case let url as URL in walk where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(base + "/") else { continue }
        files[String(path.dropFirst(base.count))] = url
      }
    }
    if let page = files["/play/index.html"] {
      files["/"] = page
      files["/play"] = page
    }
    self.files = files
  }

  /// `accent` is the host's theme's (`Theme.webAccent`): the player page is
  /// served wearing it.
  func response(to request: HTTPRequest, accent: String? = nil) -> HTTPResponse {
    guard request.method == "GET" || request.method == "HEAD" else {
      return .error(405, "Method Not Allowed")
    }
    guard let file = files[request.path], var body = try? Data(contentsOf: file) else {
      return .error(404, "Not Found")
    }
    if let accent, file == files["/"] {
      body = Self.dress(body, in: accent)
    }
    return .content(body, type: Self.contentType(of: file), includingBody: request.method == "GET")
  }

  /// The player page in the host's accent: `<html data-accent="#ffb000">`,
  /// which `theme.js` paints from `<head>`, before the page is first drawn —
  /// as the laptop server serves it in its operator's. Anything but a
  /// `#rrggbb` leaves the page as it was.
  static func dress(_ page: Data, in accent: String) -> Data {
    guard accent.wholeMatch(of: /#[0-9a-fA-F]{6}/) != nil, let tag = page.firstRange(of: Data("<html".utf8)) else {
      return page
    }
    var dressed = page
    dressed.replaceSubrange(tag, with: Data("<html data-accent=\"\(accent)\"".utf8))
    return dressed
  }

  static func contentType(of file: URL) -> String {
    switch file.pathExtension.lowercased() {
    case "html": "text/html; charset=utf-8"
    case "css": "text/css; charset=utf-8"
    case "js": "text/javascript; charset=utf-8"
    case "woff2": "font/woff2"
    case "svg": "image/svg+xml"
    case "png": "image/png"
    default: "application/octet-stream"
    }
  }
}
