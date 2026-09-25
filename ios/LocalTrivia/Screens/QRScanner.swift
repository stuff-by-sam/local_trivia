import AVFoundation
import DesignSystem
import SwiftUI
import Vision
import VisionKit

/// Reads a host's join QR code — the fallback when Bonjour can't see the game
/// (a network that filters multicast).
struct QRScannerSheet: View {
  /// Whether Trivia may use the camera. Asked for when the sheet opens, the
  /// first time; if the answer was no, the sheet says how to change it.
  enum CameraAccess {
    case allowed, notAsked, denied, restricted

    static var current: CameraAccess {
      switch AVCaptureDevice.authorizationStatus(for: .video) {
      case .authorized: .allowed
      case .notDetermined: .notAsked
      case .restricted: .restricted
      default: .denied
      }
    }
  }

  let onFound: (JoinLink) -> Void
  @State private var access: CameraAccess
  @Environment(\.dismiss) private var dismiss
  /// The last code seen wasn't a game on this network.
  @State private var isRejected = false

  init(access: CameraAccess = .current, onFound: @escaping (JoinLink) -> Void) {
    _access = State(initialValue: access)
    self.onFound = onFound
  }

  var body: some View {
    NavigationStack {
      Group {
        switch access {
        case .allowed:
          scanner
        case .notAsked:
          Color.clear
            .task {
              let allowed = await AVCaptureDevice.requestAccess(for: .video)
              access = allowed ? .allowed : .current
            }
        case .denied, .restricted:
          CameraOff(isRestricted: access == .restricted)
        }
      }
      .navigationTitle("Scan to Join")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
        }
      }
    }
  }

  private var scanner: some View {
    QRScanner { payload in
      // Only a phone host's join link: a laptop presenter's bare address
      // isn't a game this app plays.
      guard let url = URL(string: payload), let link = JoinLink(url: url) else {
        isRejected = true
        return false
      }
      onFound(link)
      dismiss()
      return true
    }
    .ignoresSafeArea()
    .overlay(alignment: .bottom) {
      Group {
        if isRejected {
          Label("That code isn't a game on this network", systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.warning)
        } else {
          Label("Point at the QR code on the host's phone", systemImage: "qrcode")
        }
      }
      .textRole(.status)
      .padding(.horizontal, Space.l)
      .frame(minHeight: Size.target)
      .glassEffect(in: .capsule)
      .padding(.horizontal, Space.screen)
      .padding(.bottom, Space.xxl)
    }
  }
}

/// The camera's off for Trivia: why there's no scanner, and the way round it.
private struct CameraOff: View {
  let isRestricted: Bool

  @Environment(\.openURL) private var openURL

  var body: some View {
    ContentUnavailableView {
      Label(isRestricted ? "Camera Restricted" : "Camera Is Off for Trivia", systemImage: "camera.fill")
    } description: {
      if isRestricted {
        Text("This iPhone doesn't allow the camera. Type the PIN from the host's phone instead.")
      } else {
        Text("To scan the host's code, allow Camera for Trivia in Settings. Or type the PIN from the host's phone.")
      }
    } actions: {
      if !isRestricted {
        Button("Open Settings") {
          if let settings = URL(string: UIApplication.openSettingsURLString) { openURL(settings) }
        }
        .buttonStyle(.glassProminent)
      }
    }
  }
}

struct QRScanner: UIViewControllerRepresentable {
  /// Returns true once a payload is accepted, which stops scanning.
  let onPayload: (String) -> Bool

  /// Whether this phone can scan codes at all. Whether Trivia may use its
  /// camera is the sheet's to find out, and explain.
  static var isSupported: Bool { DataScannerViewController.isSupported }

  func makeUIViewController(context: Context) -> DataScannerViewController {
    let scanner = DataScannerViewController(
      recognizedDataTypes: [.barcode(symbologies: [.qr])],
      qualityLevel: .fast,
      isHighFrameRateTrackingEnabled: false,
      isHighlightingEnabled: true
    )
    scanner.delegate = context.coordinator
    return scanner
  }

  func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
    context.coordinator.onPayload = onPayload
    // Scanning must start once the view is live, not while it's being built.
    if !scanner.isScanning, !context.coordinator.isFinished { try? scanner.startScanning() }
  }

  func makeCoordinator() -> Coordinator { Coordinator(onPayload: onPayload) }

  final class Coordinator: NSObject, DataScannerViewControllerDelegate {
    var onPayload: (String) -> Bool
    var isFinished = false

    init(onPayload: @escaping (String) -> Bool) { self.onPayload = onPayload }

    func dataScanner(
      _ dataScanner: DataScannerViewController,
      didAdd addedItems: [RecognizedItem],
      allItems: [RecognizedItem]
    ) {
      guard !isFinished else { return }
      for case .barcode(let code) in addedItems {
        guard let payload = code.payloadStringValue, onPayload(payload) else { continue }
        isFinished = true
        dataScanner.stopScanning()
        Haptic.found.play()
        return
      }
    }
  }
}

#if DEBUG
#Preview("Camera off") { ScreenPreview(.scannerOff) }
#Preview("Camera restricted") { ScreenPreview(.scannerRestricted) }
#endif
