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
  @Environment(\.accent) private var accent
  @Environment(\.dismiss) private var dismiss

  @State private var editing: HostQuestion?
  @State private var isImporting = false
  @State private var importReport: ImportReport?
  @State private var isConfirmingClear = false

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
          .listRowBackground(RowBackground())
        }

        questionsSection

        ScoringSection(rules: $library.rules)
          .listRowBackground(RowBackground())
      }
      .scrollContentBackground(.hidden)
      .background { Backdrop(mood: .idle, accent: accent) }
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
      // A bar, not an inset: the list softens under it with the system's
      // scroll-edge effect instead of colliding with its text.
      .safeAreaBar(edge: .bottom) {
        if !isLive { startBar }
      }
      .navigationDestination(item: $editing) { question in
        QuestionEditorView(
          question: question,
          isNew: !library.questions.contains { $0.id == question.id },
          onSave: { library.upsert($0) },
          onDelete: { deleted in library.questions.removeAll { $0.id == deleted.id } }
        )
      }
      .fileImporter(isPresented: $isImporting, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
        importReport = importCSV(result)
      }
      .alert(item: $importReport) { report in
        Alert(title: Text(report.title), message: Text(report.detail), dismissButton: .default(Text("OK")))
      }
      .confirmationDialog("Delete every question?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
        Button("Delete All Questions", role: .destructive) { library.questions = [] }
      } message: {
        Text("This can't be undone.")
      }
    }
    .preferredColorScheme(.dark)
    .tint(accent)
  }

  // MARK: - Questions

  private var questionsSection: some View {
    Section {
      if host.library.questions.isEmpty {
        Text("No questions yet. Write one, or import a CSV — the same format the web admin console takes.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .padding(.vertical, 6)
      }
      ForEach(host.library.questions) { question in
        QuestionRow(question: question) {
          toggleIncluded(question)
        } onOpen: {
          editing = question
        }
      }
      .onDelete { host.library.delete(at: $0) }
      .onMove { host.library.move(from: $0, to: $1) }

      Button {
        editing = .blank()
      } label: {
        Label("Write a Question", systemImage: "plus")
      }
      Button {
        isImporting = true
      } label: {
        Label("Import CSV…", systemImage: "square.and.arrow.down")
      }
      if !host.library.questions.isEmpty {
        Button(role: .destructive) {
          isConfirmingClear = true
        } label: {
          Label("Delete All…", systemImage: "trash")
        }
      }
    } header: {
      SectionHeader("Questions · \(host.library.playable.count) in play")
    } footer: {
      Text("Tap a question to edit it, or the circle to leave it out of this round. Swipe to delete; Edit to reorder.")
    }
    .listRowBackground(RowBackground())
  }

  private func toggleIncluded(_ question: HostQuestion) {
    var copy = question
    copy.isIncluded.toggle()
    host.library.upsert(copy)
  }

  // MARK: - Start

  private var startBar: some View {
    VStack(spacing: 10) {
      if case .failed(let reason) = host.status {
        Label(reason, systemImage: "exclamationmark.triangle.fill")
          .terminalStyle(.caption)
          .foregroundStyle(Color.broadcastRed)
      } else {
        Text(startHint)
          .terminalStyle(.caption)
          .foregroundStyle(.secondary)
      }
      Button {
        Task {
          await host.start(joining: store)
          if host.isHosting { dismiss() }
        }
      } label: {
        ZStack {
          HStack(spacing: 10) {
            Text("Start Hosting")
            Image(systemName: "antenna.radiowaves.left.and.right")
          }
          .opacity(host.status == .starting ? 0 : 1)
          if host.status == .starting {
            ProgressView().tint(Color.broadcastInk)
          }
        }
        .terminalStyle(.headline, weight: .bold)
        .foregroundStyle(canStart ? Color.broadcastInk : Color.secondary)
        .frame(maxWidth: .infinity, minHeight: 32)
      }
      .buttonStyle(.glassProminent)
      .tint(accent)
      .controlSize(.large)
      .disabled(!canStart)
    }
    .padding(.horizontal, 20)
    .padding(.top, 12)
    .padding(.bottom, 4)
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

  @Environment(\.accent) private var accent

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Button(action: onToggle) {
        Image(systemName: question.isIncluded ? "checkmark.circle.fill" : "circle")
          .font(.title3)
          .foregroundStyle(question.isIncluded ? accent : .secondary)
      }
      .buttonStyle(.borderless)
      .accessibilityLabel(question.isIncluded ? "In this round" : "Left out of this round")
      .accessibilityHint("Toggles whether this question plays.")

      Button(action: onOpen) {
        VStack(alignment: .leading, spacing: 6) {
          Text(verbatim: question.text.isEmpty ? "—" : question.text)
            .font(.body.weight(.semibold))
            .lineLimit(2)
            .foregroundStyle(question.isIncluded ? .primary : .secondary)
          if let problem = question.problem {
            Label(problem.message, systemImage: "exclamationmark.triangle.fill")
              .terminalStyle(.caption2)
              .foregroundStyle(Color.broadcastGold)
          } else if let style = AnswerStyle(rawValue: question.correct) {
            HStack(spacing: 8) {
              AnswerKey(style: style)
              Text(verbatim: question.options[question.correct])
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
              Spacer(minLength: 8)
              Text(verbatim: "\(question.category)\(question.timeLimit.map { " · \($0)S" } ?? "")")
                .terminalStyle(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
    }
    .padding(.vertical, 4)
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
      VStack(alignment: .leading, spacing: 8) {
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
        "Right in \(quickSeconds)s: \(quick.grouped) pts · right at the buzzer: \(buzzer.grouped) · wrong: \(rules.wrongAnswerPoints.grouped). Answers score more the faster they come in.\(rules.autoAdvance ? " Auto-advance moves on 5 seconds after each reveal and standings." : "")"
    )
  }
}

/// Mono, uppercase section titles, like the rest of the app's labels.
struct SectionHeader: View {
  let text: LocalizedStringKey
  init(_ text: LocalizedStringKey) { self.text = text }

  var body: some View {
    Text(text)
      .terminalStyle(.caption)
      .foregroundStyle(.secondary)
  }
}

/// Form rows as the app's readouts: a faint panel over the backdrop.
struct RowBackground: View {
  var body: some View {
    Rectangle().fill(.white.opacity(0.055))
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
