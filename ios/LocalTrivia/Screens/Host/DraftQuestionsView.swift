import DesignSystem
import SwiftUI

/// Name a topic, get a round to review: questions drafted on this iPhone,
/// each shown with its right answer marked as soon as it's passed its checks,
/// all in until the host takes one out — as many as they asked for. Nothing
/// is added until they say so.
struct DraftQuestionsView: View {
  /// The questions already in the round: drafts that repeat one are left out.
  let round: [HostQuestion]
  let onAdd: ([HostQuestion]) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var topic: String
  @State private var count = QuestionDrafter.counts.last ?? 10
  @State private var drafts: [QuestionDrafter.Draft]
  @State private var left: Set<HostQuestion.ID> = []
  @State private var isDrafting: Bool
  /// How many the last drafting asked for.
  @State private var asked: Int
  @State private var failure: QuestionDrafter.Failure?
  /// The drafting under way, stopped if the sheet closes first.
  @State private var drafting: Task<Void, Never>?
  @FocusState private var isTopicFocused: Bool

  /// The rest start where a preview wants them; the app passes a round alone.
  init(
    round: [HostQuestion], topic: String = "", drafts: [QuestionDrafter.Draft] = [], asked: Int = 0, isDrafting: Bool = false,
    onAdd: @escaping ([HostQuestion]) -> Void
  ) {
    self.round = round
    self.onAdd = onAdd
    _topic = State(initialValue: topic)
    _drafts = State(initialValue: drafts)
    _asked = State(initialValue: asked)
    _isDrafting = State(initialValue: isDrafting)
  }

  private var chosen: [HostQuestion] { drafts.filter { !left.contains($0.id) }.map(\.question) }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Topic", text: $topic, prompt: Text("90s films, the solar system…"))
            .focused($isTopicFocused)
            .submitLabel(.go)
            .onSubmit(draft)
          Picker("Questions", selection: $count) {
            ForEach(QuestionDrafter.counts, id: \.self) { Text($0, format: .number).tag($0) }
          }
          .pickerStyle(.segmented)
        } header: {
          SectionHeader("Topic")
        } footer: {
          if let failure {
            Label(failure.message, systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(.danger)
          }
        }

        if !drafts.isEmpty || isDrafting {
          Section {
            ForEach(drafts) { draft in
              DraftRow(draft: draft, isIn: !left.contains(draft.id)) {
                if left.contains(draft.id) { left.remove(draft.id) } else { left.insert(draft.id) }
              }
            }
            if isDrafting {
              Label {
                Text("Writing and checking \(min(drafts.count + 1, asked)) of \(asked)…")
                  .textRole(.detail)
                  .foregroundStyle(.secondary)
              } icon: {
                ProgressView()
              }
              .frame(minHeight: Size.target)
            }
          } header: {
            SectionHeader("Drafts · \(chosen.count) in")
          } footer: {
            VStack(alignment: .leading, spacing: Space.xs) {
              if !isDrafting, drafts.count < asked {
                Text("Only \(drafts.count) of \(asked) passed the checks on this topic. Draft again for more, or try a broader topic.")
              }
              Text("Drafted on this iPhone by Apple Intelligence, and each one checked twice. Check every answer before you play — it can still be wrong.")
            }
          }
        }
      }
      .navigationTitle("Draft Questions")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      }
      .safeAreaBar(edge: .bottom) {
        ActionBar {
          if drafts.isEmpty {
            ActionButton("Draft Questions", systemImage: "sparkles", isLoading: isDrafting, action: draft)
              .disabled(topic.trimmingCharacters(in: .whitespaces).isEmpty && !isDrafting)
          } else {
            ActionButton(addTitle, systemImage: "plus", action: add)
              .disabled(chosen.isEmpty)
            ActionButton("Draft Again", systemImage: "arrow.counterclockwise", prominence: .secondary, isLoading: isDrafting, action: draft)
          }
        }
      }
      .scrollEdgeEffectStyle(.hard, for: .bottom)
      .onAppear { if drafts.isEmpty { isTopicFocused = true } }
      .onDisappear { drafting?.cancel() }
    }
  }

  private var addTitle: LocalizedStringKey {
    "Add ^[\(chosen.count) Question](inflect: true)"
  }

  private func draft() {
    guard !isDrafting, !topic.trimmingCharacters(in: .whitespaces).isEmpty else { return }
    isTopicFocused = false
    isDrafting = true
    failure = nil
    // Drafting again means new questions: none of these comes back.
    let avoiding = round + drafts.map(\.question)
    let wanted = count
    Motion.settle.perform {
      drafts = []
      left = []
      asked = wanted
    }
    drafting = Task {
      defer { isDrafting = false }
      do throws(QuestionDrafter.Failure) {
        let result = try await QuestionDrafter.draft(topic: topic, count: wanted, avoiding: avoiding) { draft in
          Motion.settle.perform { drafts.append(draft) }
        }
        guard !Task.isCancelled else { return }
        if result.isEmpty { failure = .failed }
      } catch {
        failure = error
      }
    }
  }

  private func add() {
    onAdd(chosen)
    dismiss()
  }
}

/// A drafted question: in or out, what it asks, the answer it gives, and
/// whether that answer needs a closer look.
private struct DraftRow: View {
  let draft: QuestionDrafter.Draft
  let isIn: Bool
  let onToggle: () -> Void

  private var question: HostQuestion { draft.question }

  var body: some View {
    Button(action: onToggle) {
      HStack(alignment: .firstTextBaseline, spacing: Space.m) {
        Image(systemName: isIn ? "checkmark.circle.fill" : "circle")
          .font(.title3)
          .foregroundStyle(isIn ? AnyShapeStyle(.themeAccent) : AnyShapeStyle(.secondary))
        VStack(alignment: .leading, spacing: Space.xs) {
          Text(verbatim: question.text)
            .textRole(.bodyEmphasis)
            .foregroundStyle(isIn ? .primary : .secondary)
          if let style = AnswerStyle(rawValue: question.correct) {
            HStack(spacing: Space.s) {
              AnswerKey(style: style)
              Text(verbatim: question.options[question.correct])
                .textRole(.detail)
                .foregroundStyle(.secondary)
            }
          }
          if !draft.isConfirmed {
            Label("Double-check this answer", systemImage: "exclamationmark.triangle.fill")
              .textRole(.detail)
              .foregroundStyle(.warning)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(minHeight: Size.target)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isIn ? .isSelected : [])
    .accessibilityHint("Adds or leaves out this question.")
  }
}

#if DEBUG
#Preview("Drafting") { ScreenPreview(.drafting) }
#Preview("Drafts to review") { ScreenPreview(.drafts) }
#endif
