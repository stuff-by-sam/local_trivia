import SwiftUI
import Vision
import VisionKit

/// Reads a host's join QR code — the fallback when Bonjour can't see the game
/// (a network that filters multicast).
struct QRScannerSheet: View {
  let onFound: (JoinLink) -> Void
  @Environment(\.dismiss) private var dismiss
  /// The last code seen wasn't a game on this network.
  @State private var isRejected = false

  var body: some View {
    NavigationStack {
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
              .foregroundStyle(Color.broadcastGold)
          } else {
            Label("Point at the QR code on the host's phone", systemImage: "qrcode")
          }
        }
        .chip()
          .padding(.bottom, 32)
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
}

struct QRScanner: UIViewControllerRepresentable {
  /// Returns true once a payload is accepted, which stops scanning.
  let onPayload: (String) -> Bool

  static var isAvailable: Bool {
    DataScannerViewController.isSupported && DataScannerViewController.isAvailable
  }

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
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        return
      }
    }
  }
}
