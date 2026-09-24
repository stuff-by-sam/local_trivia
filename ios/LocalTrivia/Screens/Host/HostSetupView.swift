import DesignSystem
import SwiftUI
import UniformTypeIdentifiers

/// Setting up the round: its name, the questions, and how it scores.
///
/// Presented from the join screen to start hosting, and from the host's menu
/// between games to change the round. Everything saves as it's edited.
struct HostSetupView: View {
  /// Editing a live game's round between games, rather than starting one.
  var isLive = false

  @Environment(HostController.self) private var host
  @Environment(GameStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  @State private var editing: HostQuestion?
  @State private var isImporting = false
  @State private var importReport: ImportReport?
  @State private var undo: UndoItem?
  @State private var isDrafting = false
  /// Whether this phone's on-device model can draft questions. Checked once:
  /// a button that can't work isn't shown.
  @State private var canDraft = false

  private struct ImportReport: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
  }

  var body: some View {
    @Bindable var library = host.library
    @Bindable var store = store

    NavigationStack {
      Form {
        // Both names are fixed once hosting starts: the game is listed under
        // one, and the host is seated under the other.
        if !isLive {
          Section {
            LabeledContent {
              TextField("Trivia Night", text: $library.gameName)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            } label: {
              Text("Game name")
            }
            LabeledContent {
              TextField("Your name", text: $store.nickname)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.nickname)
            } label: {
              Text("You play as")
            }
          } header: {
            SectionHeader("Game")
          } footer: {
            Text("Players see the game name when they look for games. You play too, under your name.")
          }
        }

        questionsSection

        ScoringSection(rules: $library.rules)
      }
      .navigationTitle(isLive ? "Edit Round" : "Host a Game")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(isLive ? "Done" : "Cancel") { dismiss() }
        }
        ToolbarItem(placement: .primaryAction) {
          EditButton()
            .disabled(library.questions.isEmpty)
        }
      }
      // A bar, not an inset, with a hard edge: the list stops under it
      // rather than showing through the hint above the button.
      .safeAreaBar(edge: .bottom) {
        if !isLive { startBar }
      }
      .scrollEdgeEffectStyle(isLive ? nil : .hard, for: .bottom)
      .navigationDestination(item: $editing) { question in
        QuestionEditorView(
          question: question,
          isNew: !library.questions.contains { $0.id == question.id },
          onSave: { library.upsert($0) },
          onDelete: { deleted in
            guard let index = library.questions.firstIndex(where: { $0.id == deleted.id }) else { return }
            delete(IndexSet(integer: index))
          }
        )
      }
      .fileImporter(isPresented: $isImporting, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
        importReport = importCSV(result)
      }
      .alert(item: $importReport) { report in
        Alert(title: Text(report.title), message: Text(report.detail), dismissButton: .default(Text("OK")))
      }
      .sheet(isPresented: $isDrafting) {
        DraftQuestionsView { host.library.questions.append(contentsOf: $0) }
      }
      .task { canDraft = QuestionDrafter.isAvailable }
      // Deleting asks nothing first; it can be taken back for a few seconds —
      // offered in the start bar when there is one, so it covers nothing.
      .undoToast(isLive ? $undo : .constant(nil))
    }
  }

  // MARK: - Questions

  private var questionsSection: some View {
    Section {
      if host.library.questions.isEmpty {
        Text("No questions yet. Write one, or import a CSV — the same format the web admin console takes.")
          .textRole(.detail)
          .foregroundStyle(.secondary)
          .padding(.vertical, Space.xs)
      }
      ForEach(host.library.questions) { question in
        QuestionRow(question: question) {
          toggleIncluded(question)
        } onOpen: {
          editing = question
        }
      }
      .onDelete { delete($0) }
      .onMove { host.library.move(from: $0, to: $1) }

      Button {
        editing = .blank()
      } label: {
        Label("Write a Question", systemImage: "plus")
      }
      if canDraft {
        Button {
          isDrafting = true
        } label: {
          Label("Draft with Apple Intelligence", systemImage: "sparkles")
        }
      }
      Button {
        isImporting = true
      } label: {
        Label("Import CSV…", systemImage: "square.and.arrow.down")
      }
      if !host.library.questions.isEmpty {
        Button(role: .destructive) {
          delete(IndexSet(host.library.questions.indices))
        } label: {
          Label("Delete All", systemImage: "trash")
        }
      }
    } header: {
      SectionHeader("Questions · \(host.library.playable.count) in play")
    } footer: {
      Text("Tap a question to edit it, or the circle to leave it out of this round. Swipe to delete; Edit to reorder.")
    }
  }

  /// Deletes, and offers to put them back.
  private func delete(_ offsets: IndexSet) {
    let library = host.library
    let removed = library.delete(at: offsets)
    guard !removed.isEmpty else { return }
    let message = Self.inflected(AttributedString(localized: "Deleted ^[\(removed.count) question](inflect: true)"))
    undo = UndoItem(message) { library.reinsert(removed) }
  }

  private func toggleIncluded(_ question: HostQuestion) {
    var copy = question
    copy.isIncluded.toggle()
    host.library.upsert(copy)
  }

  // MARK: - Start

  private var startBar: some View {
    ActionBar {
      UndoBanner(item: $undo)
      if case .failed(let reason) = host.status {
        FieldMessage(Text(reason), kind: .error)
      } else {
        FieldMessage(Text(startHint), kind: .hint)
      }
      ActionButton(
        "Start Hosting",
        systemImage: "antenna.radiowaves.left.and.right",
        isLoading: host.status == .starting
      ) {
        Task {
          await host.start(joining: store)
          if host.isHosting { dismiss() }
        }
      }
      .disabled(!canStart && host.status != .starting)
    }
  }

  private var canStart: Bool {
    !host.library.playable.isEmpty && store.nicknameIsValid && host.canStart
  }

  private var startHint: String {
    if host.library.playable.isEmpty { return String(localized: "Add at least one question") }
    if !store.nicknameIsValid { return String(localized: "Enter your name to play") }
    let count = host.library.playable.count
    return Self.inflected(AttributedString(localized: "^[\(count) question](inflect: true) ready"))
  }

  // MARK: - Import

  private func importCSV(_ result: Result<URL, any Error>) -> ImportReport {
    guard case .success(let url) = result else {
      return ImportReport(title: String(localized: "Couldn't Open File"), detail: String(localized: "Pick a CSV file to import."))
    }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    // Question banks are kilobytes; anything past a few megabytes isn't one.
    guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 5_000_000,
      let data = try? Data(contentsOf: url)
    else {
      return ImportReport(title: String(localized: "Couldn't Import"), detail: String(localized: "That file couldn't be read, or it's too large."))
    }
    let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    let outcome = host.library.importCSV(text)

    var detail: [String] = []
    if !outcome.errors.isEmpty {
      detail.append(Self.inflected(AttributedString(localized: "Skipped ^[\(outcome.errors.count) row](inflect: true):")))
      detail.append(contentsOf: outcome.errors.prefix(5))
      if outcome.errors.count > 5 { detail.append("…") }
    }
    detail.append(contentsOf: outcome.notes)
    return ImportReport(
      title: Self.inflected(AttributedString(localized: "Imported ^[\(outcome.questions.count) question](inflect: true)")),
      detail: detail.joined(separator: "\n"))
  }

  /// "1 question" / "6 questions": the agreement is resolved by AttributedString.
  private static func inflected(_ text: AttributedString) -> String {
    String(text.characters)
  }
}

/// A question in the list: included or not, what it asks, and its answer.
private struct QuestionRow: View {
  let question: HostQuestion
  let onToggle: () -> Void
  let onOpen: () -> Void

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
      Button(action: onToggle) {
        Image(systemName: question.isIncluded ? "checkmark.circle.fill" : "circle")
          .font(.title3)
          .foregroundStyle(question.isIncluded ? AnyShapeStyle(.themeAccent) : AnyShapeStyle(.secondary))
          .frame(minWidth: Size.target, minHeight: Size.target)
          .contentShape(.rect)
      }
      .buttonStyle(.borderless)
      .accessibilityLabel(question.isIncluded ? "In this round" : "Left out of this round")
      .accessibilityHint("Toggles whether this question plays.")

      Button(action: onOpen) {
        VStack(alignment: .leading, spacing: Space.xs) {
          Text(verbatim: question.text.isEmpty ? "—" : question.text)
            .textRole(.bodyEmphasis)
            .lineLimit(2)
            .foregroundStyle(question.isIncluded ? .primary : .secondary)
          if let problem = question.problem {
            Label(problem.message, systemImage: "exclamationmark.triangle.fill")
              .textRole(.labelSmall)
              .foregroundStyle(.warning)
          } else if let style = AnswerStyle(rawValue: question.correct) {
            HStack(spacing: Space.s) {
              AnswerKey(style: style)
              Text(verbatim: question.options[question.correct])
                .textRole(.detail)
                .foregroundStyle(.secondary)
                .lineLimit(1)
              Spacer(minLength: Space.s)
              Text(verbatim: "\(question.category)\(question.timeLimit.map { " · \($0)S" } ?? "")")
                .textRole(.labelSmall)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
    }
    .padding(.vertical, Space.xs)
    .opacity(question.isIncluded ? 1 : 0.7)
  }
}

/// The round's rules, with a live preview of what they're worth.
struct ScoringSection: View {
  @Binding var rules: HostRules

  private static let timePresets = [10, 15, 20, 30, 45, 60, 90, 120]

  var body: some View {
    Section {
      Stepper(value: $rules.maxPoints, in: 100...10_000, step: 100) {
        LabeledContent("Top score per question") {
          Text(verbatim: rules.maxPoints.grouped).monospacedDigit()
        }
      }
      Picker("Time per question", selection: $rules.timeLimit) {
        ForEach(Array(Set(Self.timePresets + [rules.timeLimit])).sorted(), id: \.self) { seconds in
          Text("\(seconds) seconds").tag(seconds)
        }
      }
      VStack(alignment: .leading, spacing: Space.s) {
        LabeledContent("A correct answer earns at least") {
          Text(verbatim: "\(Int((rules.minCorrectFraction * 100).rounded()))%").monospacedDigit()
        }
        Slider(value: $rules.minCorrectFraction, in: HostRules.minCorrectRange, step: 0.05)
          .accessibilityLabel("Minimum share for a correct answer")
      }
      Stepper(value: $rules.wrongAnswerPoints, in: 0...1_000, step: 50) {
        LabeledContent("A wrong answer earns") {
          Text(verbatim: "\(rules.wrongAnswerPoints.grouped) pts").monospacedDigit()
        }
      }
      Toggle("Shuffle the questions", isOn: $rules.shuffle)
      Toggle("Move on automatically", isOn: $rules.autoAdvance)
    } header: {
      SectionHeader("Scoring")
    } footer: {
      Text(preview)
    }
  }

  /// "Right in 2s: 900 pts · at the buzzer: 0 · wrong: 0" — the rules, in points.
  private var preview: String {
    let limit = Double(rules.timeLimit)
    let quick = Scoring.points(isCorrect: true, elapsed: limit * 0.1, timeLimit: limit, rules: rules)
    let buzzer = Scoring.points(isCorrect: true, elapsed: limit, timeLimit: limit, rules: rules)
    let quickSeconds = Int((limit * 0.1).rounded())
    return String(
      localized:
        "Right in \(quickSeconds)s: \(quick.grouped) pts · right at the buzzer: \(buzzer.grouped) · wrong: \(rules.wrongAnswerPoints.grouped). Answers score more the faster they come in. The standings follow each reveal after 5 seconds; \(rules.autoAdvance ? "the next question follows them 5 seconds later." : "you start the next question.")"
    )
  }
}

extension HostQuestion.Problem {
  var message: LocalizedStringKey {
    switch self {
    case .missingText: "Needs a question"
    case .missingOption: "Needs all four answers"
    case .noCorrectAnswer: "Needs a correct answer"
    case .timeOutOfRange: "Time limit must be 5–600 seconds"
    }
  }
}
