import DesignSystem
import SwiftUI

/// Type the PIN, play — or host a game.
///
/// Built for the fastest path through a crowded room: the nickname is
/// remembered, the host's game is found over Bonjour while the PIN's being
/// typed, and the fourth digit joins on its own — no button to find. Nothing
/// is looked for until a player sets out to join, so the screen opens calm:
/// the game's name, a PIN to type, and Host a Game, with Settings behind one
/// button.
struct JoinView: View {
  @Environment(GameStore.self) private var store
  @Environment(GameBrowser.self) private var browser
  @Environment(Safety.self) private var safety
  @Environment(\.horizontalSizeClass) private var sizeClass
  @Environment(\.hasRoomToSpread) private var spreads

  @State private var pin = ""
  @State private var sheet: JoinSheet?
  @State private var rejectedPins = 0
  @State private var rejectedNicknames = 0
  @State private var undo: UndoItem?
  /// Join was asked for before there was a game to send it to: it goes the
  /// moment there is one.
  @State private var isWaitingForGame = false
  /// A few seconds of looking without finding a game: time to say why, and
  /// offer the QR code.
  @State private var isStillLooking = false
  @FocusState private var focus: JoinField?

  var body: some View {
    ScrollViewReader { scroller in
      Group {
        if spreads {
          spread
        } else {
          column
        }
      }
      // Moving from the PIN to the name swaps the number pad for a taller
      // keyboard, which would cover the field. Centre it — and anything said
      // about it — in what's left.
      .onChange(of: focus) { _, field in
        guard field == .nickname else { return }
        Motion.settle.perform { scroller.scrollTo(JoinField.nickname, anchor: .center) }
      }
    }
    .toolbar {
      if QRScanner.isSupported {
        ToolbarItem(placement: .topBarLeading) {
          Button("Scan QR Code", systemImage: "qrcode.viewfinder") { sheet = .scanner }
        }
      }
      ToolbarItem(placement: .topBarTrailing) {
        Button("Settings", systemImage: "gearshape") { sheet = .settings }
      }
    }
    .sheet(item: $sheet) { sheet in
      switch sheet {
      case .scanner: QRScannerSheet { store.join($0, safety: safety, browser: browser) }
      case .settings: SettingsView()
      case .hostSetup: HostSetupView()
      }
    }
    // Setting out to join: now look for the game — and ask to, the first time.
    .onChange(of: focus) { _, field in
      if field != nil { browser.start() }
    }
    // From a join link: fill the PIN in, and the form takes it from there.
    .onChange(of: store.pendingPIN, initial: true) { _, pending in
      if let pending, pin.isEmpty { pin = pending }
    }
    // Asked to join before the game was found: it joins the moment it's up.
    .onChange(of: store.connection) { _, connection in
      guard connection == .online, isWaitingForGame, !store.isRejoining else { return }
      submit()
    }
    .task(id: [browser.isLooking, store.server == nil]) {
      isStillLooking = false
      guard browser.isLooking, store.server == nil else { return }
      try? await Task.sleep(for: .seconds(6))
      guard !Task.isCancelled else { return }
      isStillLooking = true
    }
    // Just left a game: offer to take the seat back.
    .onChange(of: store.leftGame, initial: true) { _, game in
      undo = game.map { name in UndoItem(String(localized: "Left \(name)")) { store.undoLeave() } }
    }
    .onChange(of: store.joinError) { _, error in
      guard let error else { return }
      isWaitingForGame = false
      // Said aloud, not just shown: the shake and the haptic don't say why.
      AccessibilityNotification.Announcement(error.message).post()
      // Only what was wrong gets cleared: a taken name, or a host that didn't
      // answer, is no reason to make anyone type the PIN again.
      switch error.field {
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

  // MARK: - Layouts

  /// A phone: the masthead over the form, centred while they fit, and the
  /// actions at the bottom, where the thumb is — above the keyboard while
  /// it's up.
  private var column: some View {
    ScrollView {
      VStack(spacing: Space.xxl) {
        masthead
        joining
      }
      .padding(.horizontal, Space.screen)
      .padding(.vertical, Space.xl)
    }
    .defaultScrollAnchor(.center, for: .alignment)
    .scrollDismissesKeyboard(.interactively)
    // While typing, it always gives under a swipe, so a swipe down puts the
    // keyboard away even when the form fits above it. The number pad has no
    // key for that, and Host a Game waits under it.
    .scrollBounceBehavior(focus == nil ? .basedOnSize : .always)
    .safeAreaBar(edge: .bottom) { actions }
    // On a phone with the keyboard up the form runs under the bar, and the
    // nickname would show through the glass of a disabled Join button: a
    // hard edge then. Otherwise soft, so the backdrop runs to the bottom —
    // and on iPad, where the form never reaches the bar, and a hard edge
    // would only box in the column's button.
    .scrollEdgeEffectStyle(focus != nil && sizeClass == .compact ? .hard : .soft, for: .bottom)
  }

  /// A big screen: the masthead on one half, the form and its actions on the
  /// other — facing pages on iPhone Duo held like a book, the masthead above
  /// the fold and the form under the hand propped up like a laptop. While the
  /// keyboard's up over stacked halves, the form has the screen.
  private var spread: some View {
    Spread(hidesStackedLead: focus != nil) {
      masthead
    } trail: {
      ScrollView {
        joining
          .padding(.horizontal, Space.screen)
          .padding(.vertical, Space.xl)
      }
      .defaultScrollAnchor(.center, for: .alignment)
      .scrollDismissesKeyboard(.interactively)
      .scrollBounceBehavior(focus == nil ? .basedOnSize : .always)
      .safeAreaBar(edge: .bottom) { actions }
    }
  }

  // MARK: - Parts

  /// What the screen is, before anything's typed: the four marks and the name.
  private var masthead: some View {
    VStack(spacing: Space.l) {
      AnswerSetMark()
      Wordmark()
    }
    // Tapping away from the fields puts the keyboard away, as anywhere else.
    .contentShape(.rect)
    .onTapGesture { focus = nil }
  }

  @ViewBuilder
  private var joining: some View {
    if store.isRejoining {
      StatusLine(store.connection.hasFailed ? "Host unreachable, retrying" : "Rejoining your game")
    } else {
      form
    }
  }

  private var form: some View {
    VStack(spacing: Space.xl) {
      LabeledField("PIN") {
        VStack(alignment: .leading, spacing: Space.s) {
          PINField(pin: $pin, focus: $focus)
            .rejectionShake(trigger: rejectedPins)
          // Right under the cells: the keyboard can cover anything lower,
          // and this is exactly what the player is looking at.
          messages
          // The game's line has its room from the moment the look starts —
          // as the keyboard comes up — so the game turning up, or its link
          // coming online, never pushes the nickname down mid-typing.
          ZStack(alignment: .leading) {
            if browser.isLooking || store.server != nil {
              Color.clear
                .frame(height: Size.target)
            }
            game
          }
        }
        .motion(.settle, value: isStillLooking)
        .motion(.settle, value: store.server)
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
          } else if !store.nicknameIsAllowed {
            FieldMessage(Text("That nickname isn't allowed. Pick another."), kind: .error)
              .transition(.opacity)
          }
        }
        .id(JoinField.nickname)
      }
    }
  }

  /// Which game the PIN goes to, once there's one to name — or, a while into
  /// looking with none found, why that usually is and the ways round it.
  @ViewBuilder
  private var game: some View {
    if store.server != nil || games.count > 1 || isFinding {
      GamePicker(isFinding: isFinding) { sheet = .scanner }
        .transition(.opacity)
    } else if browser.isLooking, isStillLooking || browser.hasFailed {
      DiscoveryHelp(hasFailed: browser.hasFailed) { sheet = .scanner }
        .transition(.opacity)
    }
  }

  /// Join, and — when nobody's typing — Host a Game under it.
  private var actions: some View {
    ActionBar {
      UndoBanner(item: $undo, seconds: GameStore.undoWindow / .seconds(1) - 2)
      if store.isRejoining {
        ActionButton("Start Over", prominence: .secondary) { store.leave() }
      } else {
        ActionButton("Join Game", systemImage: "arrow.forward", isLoading: isBusy, action: submit)
          .disabled(!canSubmit && !isBusy)
        if focus == nil {
          ActionButton("Host a Game", systemImage: "antenna.radiowaves.left.and.right", prominence: .secondary) {
            sheet = .hostSetup
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
      }
    }
    .transition(.opacity)
  }

  // MARK: - Joining

  /// The games on the network this phone lists.
  private var games: [GameServer] { browser.games(shownBy: safety) }

  private var canSubmit: Bool { pin.count == GameStore.pinLength && store.nicknameIsValid }

  private var isBusy: Bool { store.isJoining || isFinding }

  /// Join's been asked for, and a game's still coming: one found and being
  /// dialled, or a look that's young. Several found is a choice for the
  /// player; none for a while, a reason to say why.
  private var isFinding: Bool {
    guard isWaitingForGame, store.connection != .online else { return false }
    if store.server != nil { return !store.connection.hasFailed }
    return browser.isLooking && !browser.hasFailed && !isStillLooking && games.count < 2
  }

  private func submit() {
    guard canSubmit, !store.isJoining else { return }
    focus = nil
    if store.canJoin {
      isWaitingForGame = false
      store.join(pin: pin)
    } else {
      // No game to send it to yet: look, and join the moment one's found.
      isWaitingForGame = true
      browser.start()
    }
  }
}

private enum JoinField { case pin, nickname }

/// What the join screen opens over itself.
private enum JoinSheet: Identifiable {
  case scanner, settings, hostSetup

  var id: Self { self }
}

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
  let hasFailed: Bool
  let scan: () -> Void

  @Environment(\.openURL) private var openURL

  var body: some View {
    VStack(alignment: .leading, spacing: Space.xs) {
      if hasFailed {
        FieldMessage(Text("Can't look for games. Local Network may be off for Trivia."), kind: .notice)
      } else {
        FieldMessage(Text("No game found. The host's phone has to be on this Wi-Fi."), kind: .hint)
      }
      HStack(spacing: Space.l) {
        if QRScanner.isSupported {
          QuietButton("Scan QR Code", systemImage: "qrcode.viewfinder", action: scan)
        }
        QuietButton("Local Network Settings", systemImage: "wifi") {
          if let settings = URL(string: UIApplication.openSettingsURLString) { openURL(settings) }
        }
      }
      .padding(.leading, Space.xs)
    }
  }
}

/// The game the PIN goes to, in a line: the one found, a choice when there
/// are several, or the look for one while Join waits. A menu, when there's
/// another game to pick or a camera to scan a code with.
private struct GamePicker: View {
  let isFinding: Bool
  let scan: () -> Void

  @Environment(GameStore.self) private var store
  @Environment(GameBrowser.self) private var browser
  @Environment(Safety.self) private var safety

  var body: some View {
    let games = browser.games(shownBy: safety)
    if let server = store.server {
      GameLine { status } label: {
        picker(games) {
          GameLineLabel(Text(verbatim: server.name), detail: Text(detail), isMenu: hasChoices(games))
        }
        .accessibilityLabel(Text("Game: \(server.name). \(String(localized: detail))"))
      }
    } else if games.count > 1 {
      GameLine {
        Image(systemName: "list.bullet")
          .foregroundStyle(.themeAccent)
      } label: {
        picker(games) {
          GameLineLabel(Text("Pick your game").foregroundStyle(.themeAccent), detail: Text("\(games.count) on this Wi-Fi"))
        }
      }
    } else if isFinding {
      GameLine {
        ProgressView()
          .controlSize(.mini)
      } label: {
        GameLineLabel(Text("Looking for the game"), isMenu: false)
          .accessibilityAddTraits(.updatesFrequently)
      }
    }
  }

  /// The games to pick between, and the QR code — or just the label, when
  /// there's nothing to pick.
  @ViewBuilder
  private func picker(_ games: [GameServer], @ViewBuilder label: () -> some View) -> some View {
    if hasChoices(games) {
      Menu {
        if !games.isEmpty {
          Section("On This Wi-Fi") {
            ForEach(games, id: \.self) { game in
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
            Button("Scan QR Code", systemImage: "qrcode.viewfinder", action: scan)
          }
        }
      } label: {
        label()
      }
      .buttonStyle(.plain)
      .accessibilityHint("Choose a different game.")
    } else {
      label()
    }
  }

  private func hasChoices(_ games: [GameServer]) -> Bool {
    games.contains { $0 != store.server } || QRScanner.isSupported
  }

  @ViewBuilder
  private var status: some View {
    switch store.connection {
    case .online: StatusDot(.online)
    case .connecting(let attempt) where attempt > 0: StatusDot(.failed)
    default: StatusDot(.connecting)
    }
  }

  private var detail: LocalizedStringResource {
    switch store.connection {
    case .online: "Online"
    case .connecting(let attempt) where attempt > 0: "Unreachable"
    default: "Connecting"
    }
  }
}

#if DEBUG
#Preview("At rest") { ScreenPreview(.join) }
#Preview("Game found") { ScreenPreview(.joinFound) }
#Preview("Pick a game") { ScreenPreview(.joinChoose) }
#Preview("Local Network off") { ScreenPreview(.joinNoNetwork) }
#Preview("Wrong PIN") { ScreenPreview(.joinWrongPIN) }
#Preview("Just left: undo") { ScreenPreview(.joinLeft) }
#Preview("Host ended the game") { ScreenPreview(.joinHostEnded) }
#Preview("Removed by the host") { ScreenPreview(.joinRemoved) }
#endif
