import SwiftUI
import UIKit

/// Every curve in the app: springs, interruptible, never a delay for its own
/// sake. Under Reduce Motion each becomes `reduced`, a short cross-fade.
public enum Motion: Sendable {
  /// Control state: an answer locking, a key picked, a digit landing.
  case snap
  /// Status text and small layout changes.
  case settle
  /// One game phase giving way to the next.
  case screen
  /// The backdrop's glow changing hue.
  case mood
  /// A verdict or a first place arriving.
  case pop
  /// Points counting up.
  case count

  public var animation: Animation {
    switch self {
    case .snap: .snappy(duration: 0.2)
    case .settle: .smooth(duration: 0.35)
    case .screen: .smooth(duration: 0.5)
    case .mood: .smooth(duration: 0.9)
    case .pop: .spring(duration: 0.35, bounce: 0.45)
    case .count: .snappy(duration: 0.6)
    }
  }

  public static let reduced: Animation = .smooth(duration: 0.2)

  public func animation(reduceMotion: Bool) -> Animation {
    reduceMotion ? Self.reduced : animation
  }

  /// `withAnimation`, honouring Reduce Motion — for event handlers, which
  /// can't read the environment.
  @discardableResult
  public func perform<Result>(_ body: () throws -> Result) rethrows -> Result {
    try withAnimation(animation(reduceMotion: UIAccessibility.isReduceMotionEnabled), body)
  }
}

extension View {
  /// Animates changes to `value` with `motion`, or its Reduce Motion stand-in.
  public func motion(_ motion: Motion, value: some Equatable) -> some View {
    modifier(MotionModifier(motion: motion, value: value))
  }

  /// How one screen gives way to the next: a blur, or a cross-fade under
  /// Reduce Motion.
  public func screenTransition() -> some View {
    modifier(ScreenTransition())
  }

  /// A quick head-shake and an error haptic when `trigger` changes: "not
  /// that". Just the haptic under Reduce Motion.
  public func rejectionShake(trigger: Int) -> some View {
    modifier(RejectionShake(trigger: trigger))
  }
}

private struct MotionModifier<Value: Equatable>: ViewModifier {
  let motion: Motion
  let value: Value
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content.animation(motion.animation(reduceMotion: reduceMotion), value: value)
  }
}

private struct ScreenTransition: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content.transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace))
  }
}

private struct RejectionShake: ViewModifier {
  let trigger: Int
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content
      .keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, offset in
        view.offset(x: reduceMotion ? 0 : offset)
      } keyframes: { _ in
        KeyframeTrack {
          CubicKeyframe(-14, duration: 0.07)
          CubicKeyframe(12, duration: 0.07)
          CubicKeyframe(-8, duration: 0.07)
          CubicKeyframe(0, duration: 0.09)
        }
      }
      .haptic(.rejected, trigger: trigger)
  }
}

/// Every haptic in the app, one per event. Never on scrolling or on a change
/// the player didn't cause or need to notice.
public enum Haptic: Sendable {
  case lock, correct, wrong, missed, joined, questionStart, rejected, action, found

  public var feedback: SensoryFeedback {
    switch self {
    case .lock: .impact(weight: .medium, intensity: 0.9)
    case .correct, .joined, .found: .success
    case .wrong, .rejected: .error
    case .missed: .warning
    case .questionStart: .start
    case .action: .impact(weight: .medium)
    }
  }

  /// Plays it now, for code outside SwiftUI (a camera delegate).
  public func play() {
    switch self {
    case .correct, .joined, .found: UINotificationFeedbackGenerator().notificationOccurred(.success)
    case .wrong, .rejected: UINotificationFeedbackGenerator().notificationOccurred(.error)
    case .missed: UINotificationFeedbackGenerator().notificationOccurred(.warning)
    case .lock, .action, .questionStart: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
  }
}

extension View {
  public func haptic(_ haptic: Haptic, trigger: some Equatable) -> some View {
    sensoryFeedback(haptic.feedback, trigger: trigger)
  }

  public func haptic<T: Equatable>(_ haptic: Haptic, trigger: T, condition: @escaping (T, T) -> Bool) -> some View {
    sensoryFeedback(haptic.feedback, trigger: trigger, condition: condition)
  }

  /// The haptic, if any, for a change from `old` to `new`.
  public func haptic<T: Equatable>(trigger: T, _ haptic: @escaping (T, T) -> Haptic?) -> some View {
    sensoryFeedback(trigger: trigger) { old, new in haptic(old, new)?.feedback }
  }
}
