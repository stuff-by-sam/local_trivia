import DesignSystem
import SwiftUI

/// Name a topic, get a round to review: questions drafted on this iPhone,
/// each shown with its right answer marked, all in until the host takes one
/// out. Nothing is added until they say so.
struct DraftQuestionsView: View {
  /// The questions already in the round: drafts that repeat one are left out.
  let round: [HostQuestion]
  let onAdd: ([HostQuestion]) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var topic = ""
  @State private var count = QuestionDrafter.counts.last ?? 10
  @State private var drafts: [HostQuestion] = []
  @State private var left: Set<HostQuestion.ID> = []
  @State private var isDrafting = false
  /// Drafts asked for but not shown: unusable, possibly wrong, or repeats.
  @State private var leftOut = 0
  @State private var failure: QuestionDrafter.Failure?
  @FocusState private var isTopicFocused: Bool

  private var chosen: [HostQuestion] { drafts.filter { !left.contains($0.id) } }

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

        if !drafts.isEmpty {
          Section {
            ForEach(drafts) { question in
              DraftRow(question: question, isIn: !left.contains(question.id)) {
                if left.contains(question.id) { left.remove(question.id) } else { left.insert(question.id) }
              }
            }
          } header: {
            SectionHeader("Drafts · \(chosen.count) in")
          } footer: {
            VStack(alignment: .leading, spacing: Space.xs) {
              if leftOut > 0 {
                Text("Left out ^[\(leftOut) draft](inflect: true) that could be wrong or repeat the round.")
              }
              Text("Drafted on this iPhone by Apple Intelligence. Check every answer before you play — it can be wrong.")
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
      .onAppear { isTopicFocused = true }
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
    Task {
      defer { isDrafting = false }
      do throws(QuestionDrafter.Failure) {
        let result = try await QuestionDrafter.draft(topic: topic, count: count, avoiding: round)
        Motion.settle.perform {
          drafts = result
          left = []
          leftOut = max(0, count - result.count)
        }
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

/// A drafted question: in or out, what it asks, and the answer it gives.
private struct DraftRow: View {
  let question: HostQuestion
  let isIn: Bool
  let onToggle: () -> Void

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
