import DesignSystem
import MessageUI
import SwiftUI

/// Writing a report: what's reported, why, and anything to add — then an
/// email to the developer, written out, for the person to send from Mail.
/// Nothing is sent until they do.
struct ReportSheet: View {
  @State var report: Report

  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @State private var isComposing = false
  @State private var noMail = false

  var body: some View {
    NavigationStack {
      Form {
        if let blocked = report.blocked {
          Section {
            Label { Text(blocked) } icon: { Image(systemName: "hand.raised.fill") }
              .foregroundStyle(.secondary)
          }
        }
        if !report.content.isEmpty {
          Section {
            // As it was on screen: what's reported is never Markdown or a key.
            Text(verbatim: report.content)
              .textRole(.body)
              .textSelection(.enabled)
          } header: {
            SectionHeader(verbatim: String(localized: report.kind))
          }
        }
        Section {
          Picker("Reason", selection: $report.reason) {
            ForEach(Report.Reason.allCases) { Text($0.title).tag($0) }
          }
          .pickerStyle(.inline)
          .labelsHidden()
        } header: {
          SectionHeader("What's wrong")
        }
        Section {
          TextField("Anything that would help us", text: $report.note, axis: .vertical)
            .lineLimit(3...)
        } header: {
          SectionHeader("Details")
        } footer: {
          Text("Opens an email to \(Safety.reportAddress) for you to send. We review every report within 24 hours.")
        }
      }
      .navigationTitle("Report")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      }
      .safeAreaBar(edge: .bottom) {
        ActionBar {
          ActionButton("Send Report", systemImage: "paperplane.fill", action: send)
        }
      }
      .scrollEdgeEffectStyle(.hard, for: .bottom)
      .sheet(isPresented: $isComposing) {
        MailComposer(report: report) { sent in
          isComposing = false
          if sent { dismiss() }
        }
        .ignoresSafeArea()
      }
      .alert("No Mail Account", isPresented: $noMail) {
        Button("Copy Report") {
          UIPasteboard.general.string = "To: \(Safety.reportAddress)\nSubject: \(report.mailSubject)\n\n\(report.mailBody())"
          dismiss()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Copy the report and email it to \(Safety.reportAddress).")
      }
    }
  }

  /// Apple's Mail when it's set up; otherwise whatever mail app the phone
  /// has; otherwise the report to copy.
  private func send() {
    if MFMailComposeViewController.canSendMail() {
      isComposing = true
    } else if let url = report.mailURL {
      openURL(url) { accepted in
        if accepted { dismiss() } else { noMail = true }
      }
    } else {
      noMail = true
    }
  }
}

/// Mail's compose sheet, written out with the report.
private struct MailComposer: UIViewControllerRepresentable {
  let report: Report
  let onFinish: (_ sent: Bool) -> Void

  func makeUIViewController(context: Context) -> MFMailComposeViewController {
    let mail = MFMailComposeViewController()
    mail.mailComposeDelegate = context.coordinator
    mail.setToRecipients([Safety.reportAddress])
    mail.setSubject(report.mailSubject)
    mail.setMessageBody(report.mailBody(), isHTML: false)
    return mail
  }

  func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

  func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

  final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
    let onFinish: (Bool) -> Void

    init(onFinish: @escaping (Bool) -> Void) {
      self.onFinish = onFinish
    }

    nonisolated func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: (any Error)?) {
      MainActor.assumeIsolated {
        onFinish(result == .sent || result == .saved)
      }
    }
  }
}

extension View {
  /// Shows `report` as it's being written, and clears it when the sheet goes.
  func reportSheet(_ report: Binding<Report?>) -> some View {
    sheet(item: report) { ReportSheet(report: $0) }
  }
}

#if DEBUG
#Preview("Report a question") {
  ReportSheet(report: Report(.question(text: "Which planet has the most moons?", options: ["Jupiter", "Saturn", "Uranus", "Neptune"], category: "SPACE"), gameName: "Friday Quiz", isHost: false))
}
#endif
