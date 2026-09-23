import SwiftUI

/// Something that just happened and can be taken back for a few seconds —
/// in place of asking "are you sure?" first.
public struct UndoItem: Identifiable {
  public let id = UUID()
  public let message: String
  public let undo: () -> Void

  public init(_ message: String, undo: @escaping () -> Void) {
    self.message = message
    self.undo = undo
  }
}

extension View {
  /// Shows `item` as a toast at the bottom with an Undo button, for
  /// `seconds`, then lets it go. VoiceOver hears the message.
  public func undoToast(_ item: Binding<UndoItem?>, seconds: Double = 6) -> some View {
    modifier(UndoToastModifier(item: item, seconds: seconds))
  }
}

private struct UndoToastModifier: ViewModifier {
  @Binding var item: UndoItem?
  let seconds: Double

  func body(content: Content) -> some View {
    content
      .overlay(alignment: .bottom) {
        if let current = item {
          UndoToast(item: current) {
            current.undo()
            item = nil
          }
          .padding(.horizontal, Space.screen)
          .padding(.bottom, Space.s)
          .transition(.move(edge: .bottom).combined(with: .opacity))
          .task(id: current.id) {
            AccessibilityNotification.Announcement(current.message).post()
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, item?.id == current.id else { return }
            Motion.settle.perform { item = nil }
          }
        }
      }
      .motion(.settle, value: item?.id)
  }
}

struct UndoToast: View {
  let item: UndoItem
  let onUndo: () -> Void

  var body: some View {
    HStack(spacing: Space.m) {
      Text(verbatim: item.message)
        .textRole(.status)
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
      Button("Undo", action: onUndo)
        .textRole(.action)
        .buttonStyle(.glassProminent)
        .foregroundStyle(.onAccent)
    }
    .padding(.leading, Space.l)
    .padding(.trailing, Space.xs)
    .frame(minHeight: Size.field)
    .glassEffect(in: .capsule)
    .accessibilityElement(children: .contain)
  }
}
