import DesignSystem
import SwiftUI

/// Find a game, type the PIN, play — or host one.
///
/// Built for the fastest path through a crowded room: the host's game is found
/// over Bonjour before the player looks for it, the nickname is remembered, and
/// the fourth PIN digit joins on its own — no button to find.
struct JoinView: View {
  @Environment(GameStore.self) private var store
  @Environment(GameBrowser.self) private var browser

  @State private var pin = ""
  @State private var isScanning = false
  @State private var rejectedPins = 0
  @State private var rejectedNicknames = 0
  @State private var isSettingUpHost = false
  @State private var isShopping = false
  @State private var undo: UndoItem?
  /// A few seconds without finding a game: time to say why, and offer the QR code.
  @State private var isStillLooking = false
  @FocusState private var focus: JoinField?

  var body: some View {
    ScrollViewReader { scroller in
      ScrollView {
        VStack(spacing: Space.xl) {
          VStack(spacing: Space.l) {
            AnswerSetMark()
            Wordmark()
          }
          .padding(.top, Space.l)

          LabeledField("Game") {
            VStack(alignment: .leading, spacing: Space.s) {
              GamePicker(isScanning: $isScanning)
              if store.server == nil, isStillLooking || browser.hasFailed {
                DiscoveryHelp(isScanning: $isScanning, hasFailed: browser.hasFailed)
                  .transition(.opacity)
              }
            }
            .motion(.settle, value: isStillLooking)
          }

          if store.isRejoining {
            StatusLine(store.connection.hasFailed ? "Host unreachable, retrying" : "Rejoining your game")
              .padding(.top, Space.s)
          } else {
            form
          }
        }
        .padding(.horizontal, Space.screen)
        .padding(.bottom, Space.xl)
      }
      .scrollDismissesKeyboard(.interactively)
      .scrollBounceBehavior(.basedOnSize)
      .safeAreaBar(edge: .bottom) { actions }
      // Moving from the PIN to the name swaps the number pad for a taller
      // keyboard, which would cover the field. Centre it — and anything said
      // about it — in what's left.
      .onChange(of: focus) { _, field in
        guard field == .nickname else { return }
        Motion.settle.perform { scroller.scrollTo(JoinField.nickname, anchor: .center) }
      }
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Themes & Icons", systemImage: "paintpalette") { isShopping = true }
      }
    }
    .sheet(isPresented: $isScanning) {
      QRScannerSheet { store.join($0.server, pin: $0.pin) }
    }
    .sheet(isPresented: $isSettingUpHost) {
      HostSetupView()
    }
    .sheet(isPresented: $isShopping) {
      ShopView()
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
    .task(id: store.server == nil) {
      isStillLooking = false
      guard store.server == nil else { return }
      try? await Task.sleep(for: .seconds(6))
      guard !Task.isCancelled else { return }
      isStillLooking = true
    }
    // Just left a game: offer to take the seat back.
    .onChange(of: store.leftGame, initial: true) { _, game in
      undo = game.map { name in UndoItem(String(localized: "Left \(name)")) { store.undoLeave() } }
    }
    .onChange(of: store.joinError) { _, error in
      // Said aloud, not just shown: the shake and the haptic don't say why.
      if let error { AccessibilityNotification.Announcement(error.message).post() }
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
    VStack(spacing: Space.xl) {
      LabeledField("PIN") {
        VStack(alignment: .leading, spacing: Space.m) {
          PINField(pin: $pin, focus: $focus)
            .rejectionShake(trigger: rejectedPins)
          // Right under the cells: the keyboard can cover anything lower,
          // and this is exactly what the player is looking at.
          messages
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
        VStack(alignment: .leading, spacing: Space.m) {
          nicknameField
            .rejectionShake(trigger: rejectedNicknames)
          if let error = store.joinError, error.field == .nickname {
            FieldMessage(Text(error.message), kind: .error)
              .transition(.opacity)
          }
        }
        .id(JoinField.nickname)
      }
    }
  }

  /// Join, and — when nobody's typing — Host a Game under it. At the bottom,
  /// where the thumb is; above the keyboard while it's up.
  private var actions: some View {
    ActionBar {
      UndoBanner(item: $undo, seconds: GameStore.undoWindow / .seconds(1) - 2)
      if store.isRejoining {
        ActionButton("Start Over", prominence: .secondary) { store.leave() }
      } else {
        ActionButton(
          "Join Game",
          systemImage: "arrow.forward",
          isLoading: store.isJoining,
          action: submit
        )
        .disabled(!(store.canJoin && pin.count == GameStore.pinLength) && !store.isJoining)
        if focus == nil {
          ActionButton("Host a Game", systemImage: "antenna.radiowaves.left.and.right", prominence: .secondary) {
            isSettingUpHost = true
          }
          .transition(.opacity)
        }
      }
    }
    .motion(.settle, value: focus == nil)
  }

  private var nicknameField: some View {
    @Bindable var store = store
    return PromptField {
      TextField("Nickname", text: $store.nickname, prompt: Text("your name"))
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
  }

  @ViewBuilder
  private var messages: some View {
    Group {
      // A nickname error sits under the nickname instead.
      if let error = store.joinError, error.field != .nickname {
        FieldMessage(Text(error.message), kind: .error)
      } else if let notice = store.notice {
        FieldMessage(Text(notice), kind: .notice)
      } else {
        FieldMessage(Text("The PIN is on the host's phone"), kind: .hint)
      }
    }
    .transition(.opacity)
  }

  private func submit() {
    guard pin.count == GameStore.pinLength else { return }
    focus = nil
    store.join(pin: pin)
  }
}

private enum JoinField { case pin, nickname }

/// The PIN's cells, with a real text field laid over them: invisible, but it
/// owns focus, the number pad, paste, and what VoiceOver reads.
private struct PINField: View {
  @Binding var pin: String
  var focus: FocusState<JoinField?>.Binding

  var body: some View {
    ZStack {
      PINCells(pin: pin, length: GameStore.pinLength, isFocused: focus.wrappedValue == .pin)

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

/// No game found: why that usually is, and the two ways out — the host's QR
/// code, and the Local Network switch in Settings.
private struct DiscoveryHelp: View {
  @Binding var isScanning: Bool
  let hasFailed: Bool

  @Environment(\.openURL) private var openURL

  var body: some View {
    VStack(alignment: .leading, spacing: Space.xs) {
      if hasFailed {
        FieldMessage(Text("Can't look for games. Local Network may be off for Trivia."), kind: .notice)
      } else {
        FieldMessage(Text("No games yet. The host's phone has to be on this Wi-Fi."), kind: .hint)
      }
      HStack(spacing: Space.l) {
        if QRScanner.isSupported {
          QuietButton("Scan QR Code", systemImage: "qrcode.viewfinder") { isScanning = true }
        }
        QuietButton("Local Network Settings", systemImage: "gearshape") {
          if let settings = URL(string: UIApplication.openSettingsURLString) { openURL(settings) }
        }
      }
      .padding(.leading, Space.xs)
    }
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
      if QRScanner.isSupported {
        Section {
          Button("Scan QR Code", systemImage: "qrcode.viewfinder") { isScanning = true }
        }
      }
    } label: {
      PickerRow(title: title, detail: detail) { status }
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
      case .online: StatusDot(.online)
      case .connecting(let attempt) where attempt > 0: StatusDot(.failed)
      default: StatusDot(.connecting)
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
