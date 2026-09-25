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

/// The undo offer, in place: a message and an Undo button that go away by
/// themselves. Put it where the screen's actions are — inside an `ActionBar`
/// — so it never covers them. VoiceOver hears the message.
public struct UndoBanner: View {
  @Binding var item: UndoItem?
  let seconds: Double

  public init(item: Binding<UndoItem?>, seconds: Double = 6) {
    _item = item
    self.seconds = seconds
  }

  public var body: some View {
    Group {
      if let current = item {
        UndoToast(item: current) {
          current.undo()
          item = nil
        }
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

extension View {
  /// Shows `item` as a toast along the bottom, for screens with no action bar
  /// to put an `UndoBanner` in.
  public func undoToast(_ item: Binding<UndoItem?>, seconds: Double = 6) -> some View {
    overlay(alignment: .bottom) {
      UndoBanner(item: item, seconds: seconds)
        .dynamicTypeSize(...Size.barTypeLimit)
        .padding(.horizontal, Space.screen)
        .padding(.bottom, Space.s)
    }
  }
}

struct UndoToast: View {
  let item: UndoItem
  let onUndo: () -> Void

  @Environment(\.dynamicTypeSize) private var typeSize

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
        .accessibilityShowsLargeContentViewer()
    }
    .padding(.leading, Space.l)
    .padding(.trailing, Space.xs)
    .frame(minHeight: Size.field)
    // A capsule on one line; at accessibility sizes the message wraps, and
    // a capsule's ends would crowd it.
    .glassEffect(in: typeSize.isAccessibilitySize ? AnyShape(.rect(cornerRadius: Radius.control)) : AnyShape(.capsule))
    .accessibilityElement(children: .contain)
  }
}
