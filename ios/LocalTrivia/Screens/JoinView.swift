import SwiftUI

/// Find a game, type the PIN, play — or host one.
///
/// Built for the fastest path through a crowded room: the host's game is found
/// over Bonjour before the player looks for it, the nickname is remembered, and
/// the fourth PIN digit joins on its own — no button to find.
struct JoinView: View {
  @Environment(GameStore.self) private var store
  @Environment(\.accent) private var accent

  @State private var pin = ""
  @State private var isScanning = false
  @State private var rejectedPins = 0
  @State private var rejectedNicknames = 0
  @State private var isSettingUpHost = false
  @FocusState private var focus: JoinField?

  var body: some View {
    ScrollViewReader { scroller in
      ScrollView {
        VStack(spacing: 30) {
          Wordmark()
            .padding(.top, 28)

          LabeledField("Game") {
            GamePicker(isScanning: $isScanning)
          }

          if store.isRejoining {
            rejoining
          } else {
            form
          }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
      }
      // Moving from the PIN to the name swaps the number pad for a taller
      // keyboard, which would cover the field. Centre it — and anything said
      // about it — in what's left.
      .onChange(of: focus) { _, field in
        guard field == .nickname else { return }
        withAnimation(.smooth) { scroller.scrollTo(JoinField.nickname, anchor: .center) }
      }
    }
    .scrollDismissesKeyboard(.interactively)
    .scrollBounceBehavior(.basedOnSize)
    .sheet(isPresented: $isScanning) {
      QRScannerSheet { store.join($0.server, pin: $0.pin) }
    }
    .sheet(isPresented: $isSettingUpHost) {
      HostSetupView()
    }
    // From a join link: fill the PIN in, and the form takes it from there.
    .onChange(of: store.pendingPIN, initial: true) { _, pending in
      if let pending, pin.isEmpty { pin = pending }
    }
    .onChange(of: store.connection) { _, connection in
      guard connection == .online, !store.isRejoining else { return }
      // A PIN typed while the link was still coming up joins the moment it's up.
      if pin.count == GameStore.pinLength, store.nicknameIsValid {
        submit()
      } else if focus == nil {
        // Otherwise put the cursor where the next keystroke goes.
        focus = store.nicknameIsValid ? .pin : .nickname
      }
    }
    .task {
      // Arriving here already online — after leaving, or being removed — no
      // connection change will fire, so put the cursor in place now, once the
      // screen has settled.
      guard store.connection == .online, !store.isRejoining else { return }
      try? await Task.sleep(for: .milliseconds(450))
      guard !Task.isCancelled, focus == nil else { return }
      focus = store.nicknameIsValid ? .pin : .nickname
    }
    .onChange(of: store.joinError) { _, error in
      // Only what was wrong gets cleared: a taken name, or a host that didn't
      // answer, is no reason to make anyone type the PIN again.
      switch error?.field {
      case .pin:
        pin = ""
        rejectedPins += 1
        focus = .pin
      case .nickname:
        rejectedNicknames += 1
        focus = .nickname
      case nil:
        break
      }
    }
  }

  // MARK: - Form

  private var form: some View {
    VStack(spacing: 22) {
      LabeledField("PIN") {
        VStack(alignment: .leading, spacing: 12) {
          pinCells
          // Right under the cells: the keyboard can cover anything lower,
          // and this is exactly what the player is looking at.
          messages
            .padding(.leading, 4)
        }
      }
      .onChange(of: pin) { _, typed in
        let digits = String(typed.filter { $0.isASCII && $0.isNumber }.prefix(GameStore.pinLength))
        if digits != typed {
          pin = digits
          return
        }
        guard digits.count == GameStore.pinLength else { return }
        if store.nicknameIsValid {
          submit()
        } else {
          focus = .nickname
        }
      }

      LabeledField("Nickname") {
        VStack(alignment: .leading, spacing: 12) {
          nicknameField
            .modifier(RejectionShake(trigger: rejectedNicknames))
          if let error = store.joinError, error.field == .nickname {
            Label(error.message, systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(Color.broadcastRed)
              .terminalStyle(.caption)
              .multilineTextAlignment(.leading)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.leading, 4)
              .transition(.opacity)
          }
        }
        .id(JoinField.nickname)
      }

      joinButton
        .padding(.top, 4)

      hostButton
    }
  }

  /// Every game is hosted from a phone, and anyone can host one.
  private var hostButton: some View {
    VStack(spacing: 10) {
      HStack(spacing: 12) {
        Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
        Text("or")
          .terminalStyle(.caption2)
          .foregroundStyle(.tertiary)
        Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
      }
      .accessibilityHidden(true)
      Button {
        isSettingUpHost = true
      } label: {
        Label("Host a Game", systemImage: "antenna.radiowaves.left.and.right")
          .terminalStyle(.footnote, weight: .bold)
          .frame(maxWidth: .infinity, minHeight: 28)
      }
      .buttonStyle(.glass)
      .controlSize(.large)
    }
    .padding(.top, 10)
  }

  private var pinCells: some View {
    PINField(pin: $pin, focus: $focus)
      .modifier(RejectionShake(trigger: rejectedPins))
  }

  private var nicknameField: some View {
    @Bindable var store = store
    return HStack(spacing: 12) {
      Text(verbatim: ">")
        .font(.mono(.title3, weight: .bold))
        .foregroundStyle(accent)
        .accessibilityHidden(true)
      TextField("Nickname", text: $store.nickname, prompt: Text("your name"))
        .font(.mono(.title3, weight: .semibold))
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .textContentType(.nickname)
        .submitLabel(.join)
        .focused($focus, equals: .nickname)
        .onSubmit {
          if pin.count == GameStore.pinLength { submit() } else { focus = .pin }
        }
        .onChange(of: store.nickname) { _, name in
          // Same limit the server applies, measured the way it measures
          // (UTF-16), trimming whole characters so an emoji is never halved.
          guard name.utf16.count > GameStore.nicknameLimit else { return }
          var clamped = name
          while clamped.utf16.count > GameStore.nicknameLimit { clamped.removeLast() }
          store.nickname = clamped
        }
    }
    .padding(.horizontal, 18)
    .frame(minHeight: 58)
    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
  }

  private var joinButton: some View {
    let isReady = store.canJoin && pin.count == GameStore.pinLength
    return Button(action: submit) {
      ZStack {
        HStack(spacing: 10) {
          Text("Join Game")
          Image(systemName: "arrow.right")
        }
        .opacity(store.isJoining ? 0 : 1)
        if store.isJoining {
          ProgressView()
            .tint(Color.broadcastInk)
        }
      }
      .terminalStyle(.headline, weight: .bold)
      .foregroundStyle(isReady || store.isJoining ? Color.broadcastInk : Color.secondary)
      .frame(maxWidth: .infinity, minHeight: 32)
    }
    .buttonStyle(.glassProminent)
    .tint(accent)
    .controlSize(.large)
    .disabled(!isReady)
  }

  @ViewBuilder
  private var messages: some View {
    Group {
      // A nickname error sits under the nickname instead.
      if let error = store.joinError, error.field != .nickname {
        Label(error.message, systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(Color.broadcastRed)
      } else if let notice = store.notice {
        Label(notice, systemImage: "hand.raised.fill")
          .foregroundStyle(Color.broadcastGold)
      } else {
        Text("The PIN is on the host's phone")
          .foregroundStyle(.tertiary)
      }
    }
    .terminalStyle(.caption)
    .multilineTextAlignment(.leading)
    .frame(maxWidth: .infinity, alignment: .leading)
    .transition(.opacity)
  }

  private var rejoining: some View {
    VStack(spacing: 22) {
      StatusLine(store.connection.hasFailed ? "Host unreachable, retrying" : "Rejoining your game")
      Button("Start Over") { store.leave() }
        .terminalStyle(.footnote, weight: .bold)
        .buttonStyle(.glass)
        .controlSize(.large)
    }
    .padding(.top, 8)
  }

  private func submit() {
    guard pin.count == GameStore.pinLength else { return }
    focus = nil
    store.join(pin: pin)
  }
}

private enum JoinField { case pin, nickname }

/// A quick head-shake and an error haptic: "not that".
private struct RejectionShake: ViewModifier {
  let trigger: Int

  func body(content: Content) -> some View {
    content
      .keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, offset in
        view.offset(x: offset)
      } keyframes: { _ in
        KeyframeTrack {
          CubicKeyframe(-14, duration: 0.07)
          CubicKeyframe(12, duration: 0.07)
          CubicKeyframe(-8, duration: 0.07)
          CubicKeyframe(0, duration: 0.09)
        }
      }
      .sensoryFeedback(.error, trigger: trigger)
  }
}

/// A mono label over its control, like a form in a terminal.
private struct LabeledField<Content: View>: View {
  let label: LocalizedStringKey
  @ViewBuilder var content: Content

  init(_ label: LocalizedStringKey, @ViewBuilder content: () -> Content) {
    self.label = label
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Text(label)
        .terminalStyle(.caption)
        .foregroundStyle(.secondary)
        .padding(.leading, 4)
        .accessibilityHidden(true)
      content
    }
  }
}

/// Four cells, one digit each, with the cursor in the next empty one.
///
/// The cells only draw. A real text field sits over them — invisible, but it
/// owns focus, the number pad, paste, and what VoiceOver reads — so the
/// custom look costs nothing in behaviour or accessibility.
private struct PINField: View {
  @Binding var pin: String
  var focus: FocusState<JoinField?>.Binding

  @Environment(\.accent) private var accent

  var body: some View {
    let digits = Array(pin)
    let isFocused = focus.wrappedValue == .pin
    ZStack {
      HStack(spacing: 10) {
        ForEach(0..<GameStore.pinLength, id: \.self) { index in
          let isNext = isFocused && index == digits.count
          ZStack {
            if index < digits.count {
              Text(String(digits[index]))
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            } else if isNext {
              BlinkingCursor()
                .foregroundStyle(accent)
            } else {
              // A faint slot, so four empty cells read as four digits to fill.
              Text(verbatim: "_")
                .foregroundStyle(.white.opacity(0.14))
            }
          }
          .font(.mono(size: 34, weight: .bold))
          .frame(maxWidth: .infinity, minHeight: 72)
          .glassEffect(in: .rect(cornerRadius: 16))
          .overlay {
            // The cell the next digit lands in: lit edge, not a filled one.
            RoundedRectangle(cornerRadius: 16)
              .strokeBorder(accent.opacity(isNext ? 0.75 : 0), lineWidth: 1.5)
              .shadow(color: accent.opacity(isNext ? 0.4 : 0), radius: 6)
          }
        }
      }
      .animation(.snappy(duration: 0.18), value: pin)
      .accessibilityHidden(true)

      TextField("", text: $pin)
        .keyboardType(.numberPad)
        .focused(focus, equals: .pin)
        .foregroundStyle(.clear)
        .tint(.clear)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Game PIN")
        .accessibilityHint("The four-digit PIN on the host's phone.")
    }
    .contentShape(.rect)
    .onTapGesture { focus.wrappedValue = .pin }
  }
}

/// The answer set above the name, and a cursor after it.
private struct Wordmark: View {
  @Environment(\.accent) private var accent

  var body: some View {
    VStack(spacing: 18) {
      HStack(spacing: 16) {
        ForEach(AnswerStyle.allCases) { style in
          Image(systemName: style.symbol)
            .foregroundStyle(style.color)
        }
      }
      .font(.body)
      .padding(.horizontal, 20)
      .padding(.vertical, 11)
      .glassEffect(in: .capsule)

      Text(verbatim: "TRIVIA")
        .tracking(6)
        // Hangs past the word rather than sitting in the row, so "TRIVIA"
        // itself is what's centred. (The offset evens out tracking's trailing gap.)
        .overlay(alignment: .trailing) {
          BlinkingCursor(glyph: "█")
            .fixedSize()
            .alignmentGuide(.trailing) { $0[.leading] }
        }
        .offset(x: 3)
      .font(.mono(size: 46, weight: .heavy))
      .foregroundStyle(accent)
      // The TV's phosphor bloom, carried over.
      .shadow(color: accent.opacity(0.45), radius: 14)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Trivia")
    .accessibilityAddTraits(.isHeader)
  }
}

/// Which game you're joining, and how to pick another.
private struct GamePicker: View {
  @Environment(GameStore.self) private var store
  @Environment(GameBrowser.self) private var browser
  @Binding var isScanning: Bool

  var body: some View {
    Menu {
      if browser.games.isEmpty {
        // Never an empty menu, even where there's no camera to scan with.
        Text("No games on this network yet")
      } else {
        Section("On This Network") {
          ForEach(browser.games, id: \.self) { game in
            Button {
              store.connect(to: game)
            } label: {
              Label(game.name, systemImage: game == store.server ? "checkmark" : "iphone")
            }
          }
        }
      }
      if QRScanner.isAvailable {
        Section {
          Button("Scan QR Code", systemImage: "qrcode.viewfinder") { isScanning = true }
        }
      }
    } label: {
      HStack(spacing: 14) {
        status
          .frame(width: 16)
        VStack(alignment: .leading, spacing: 4) {
          Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
          Text(detail)
            .font(.mono(.caption, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        Spacer(minLength: 0)
        Image(systemName: "chevron.up.chevron.down")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.tertiary)
      }
      .padding(.horizontal, 18)
      .frame(minHeight: 66)
      .contentShape(.rect)
      .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text("Game: \(title). \(detail)"))
    .accessibilityHint("Choose a different game.")
  }

  @ViewBuilder
  private var status: some View {
    if store.server == nil {
      ProgressView()
        .controlSize(.small)
    } else {
      switch store.connection {
      case .online:
        StatusDot(color: .broadcastGreen)
      case .connecting(let attempt) where attempt > 0:
        StatusDot(color: .broadcastGold, isPulsing: true)
      default:
        StatusDot(color: .secondary, isPulsing: true)
      }
    }
  }

  private var title: String {
    store.server?.name ?? String(localized: "Looking for games…")
  }

  private var detail: String {
    guard let server = store.server else {
      // Short enough for one line; scanning lives in the menu.
      return String(localized: "JOIN THE HOST'S WI-FI")
    }
    switch store.connection {
    case .online: return String(localized: "\(server.address) · ONLINE")
    case .connecting(let attempt) where attempt > 0: return String(localized: "\(server.address) · UNREACHABLE")
    default: return String(localized: "\(server.address) · CONNECTING")
    }
  }
}
