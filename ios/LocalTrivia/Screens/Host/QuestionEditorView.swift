import DesignSystem
import SwiftUI

/// Writing or editing one question: the question, four answers (tap a key to
/// mark the right one), and optionally a category and its own time limit.
struct QuestionEditorView: View {
  let isNew: Bool
  let onSave: (HostQuestion) -> Void
  let onDelete: (HostQuestion) -> Void

  @State private var draft: HostQuestion
  @Environment(\.dismiss) private var dismiss
  @FocusState private var focus: Field?

  private enum Field: Hashable { case question, answer(Int), category }

  private static let timePresets = [10, 15, 20, 30, 45, 60, 90, 120]

  init(question: HostQuestion, isNew: Bool, onSave: @escaping (HostQuestion) -> Void, onDelete: @escaping (HostQuestion) -> Void) {
    _draft = State(initialValue: question)
    self.isNew = isNew
    self.onSave = onSave
    self.onDelete = onDelete
  }

  var body: some View {
    Form {
      Section {
        TextField("What's the question?", text: $draft.text, axis: .vertical)
          .textRole(.question(length: .max))
          .lineLimit(2...6)
          .focused($focus, equals: .question)
          .submitLabel(.next)
      } header: {
        SectionHeader("Question")
      }

      Section {
        ForEach(AnswerStyle.allCases) { style in
          answerRow(style)
        }
      } header: {
        SectionHeader("Answers")
      } footer: {
        Text("Tap a key to mark the right answer.")
      }

      Section {
        LabeledContent("Category") {
          TextField("General", text: $draft.category)
            .multilineTextAlignment(.trailing)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .focused($focus, equals: .category)
        }
        Picker("Time limit", selection: $draft.timeLimit) {
          Text("Round's default").tag(Int?.none)
          ForEach(Array(Set(Self.timePresets + (draft.timeLimit.map { [$0] } ?? []))).sorted(), id: \.self) { seconds in
            Text("\(seconds) seconds").tag(Int?.some(seconds))
          }
        }
        Toggle("Play in this round", isOn: $draft.isIncluded)
      } header: {
        SectionHeader("Details")
      }

      if !isNew {
        Section {
          Button("Delete Question", role: .destructive) {
            onDelete(draft)
            dismiss()
          }
        }
      }
    }
    .navigationTitle(isNew ? "New Question" : "Edit Question")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          onSave(draft)
          dismiss()
        }
        .disabled(draft.problem != nil)
      }
    }
    .onAppear {
      if isNew { focus = .question }
    }
  }

  private func answerRow(_ style: AnswerStyle) -> some View {
    let isCorrect = draft.correct == style.rawValue
    return HStack(spacing: Space.s) {
      Button {
        draft.correct = style.rawValue
      } label: {
        AnswerKey(style: style, isInverted: isCorrect)
          .background(isCorrect ? style.color : .clear, in: .rect(cornerRadius: Radius.minimum))
          .frame(minWidth: Size.target, minHeight: Size.target)
          .contentShape(.rect)
      }
      .buttonStyle(.borderless)
      .accessibilityLabel(Text("Mark \(style.letter) as the right answer"))
      .accessibilityAddTraits(isCorrect ? .isSelected : [])

      TextField(text: $draft.options[style.rawValue], axis: .vertical) {
        Text("Answer \(style.letter)")
      }
      .lineLimit(1...3)
      .focused($focus, equals: .answer(style.rawValue))

      if isCorrect {
        Image(systemName: "checkmark")
          .fontWeight(.bold)
          .foregroundStyle(style.color)
          .accessibilityHidden(true)
      }
    }
    .motion(.snap, value: draft.correct)
  }
}
