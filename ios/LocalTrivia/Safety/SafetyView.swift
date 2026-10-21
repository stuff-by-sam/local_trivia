import DesignSystem
import SwiftUI

/// Safety, from the join screen: the terms, a way to report anything, and
/// everyone this phone has blocked — each of whom can be unblocked.
struct SafetyView: View {
  @Environment(Safety.self) private var safety
  @Environment(\.dismiss) private var dismiss
  @State private var report: Report?

  var body: some View {
    NavigationStack {
      List {
        Section {
          NavigationLink {
            TermsView()
          } label: {
            Label("Terms of Use", systemImage: "doc.text")
          }
          Button {
            report = Report(.problem, gameName: nil, isHost: false)
          } label: {
            Label("Report a Problem", systemImage: "exclamationmark.bubble")
          }
        } footer: {
          Text("In a game, report a question, a player or the game from the game's menu, or by touching and holding a name. Reports go to \(Safety.reportAddress), and we review every one within 24 hours.")
        }

        Section {
          if safety.blockedHosts.isEmpty {
            Text("Nobody").foregroundStyle(.secondary)
          }
          ForEach(safety.blockedHosts) { host in
            BlockedRow(name: host.name, detail: host.address, date: host.date) { safety.unblock(host) }
          }
        } header: {
          SectionHeader("Blocked hosts")
        } footer: {
          Text("Their games aren't listed on this phone.")
        }

        Section {
          if safety.hiddenNames.isEmpty {
            Text("Nobody").foregroundStyle(.secondary)
          }
          ForEach(safety.hiddenNames) { name in
            BlockedRow(name: name.nickname, detail: nil, date: name.date) { safety.unhide(name) }
          }
        } header: {
          SectionHeader("Blocked players")
        } footer: {
          Text("Their names are hidden in the standings on this phone.")
        }

        Section {
          if safety.blockedPlayers.isEmpty {
            Text("Nobody").foregroundStyle(.secondary)
          }
          ForEach(safety.blockedPlayers) { player in
            BlockedRow(name: player.nickname, detail: nil, date: player.date) { safety.unblock(player) }
          }
        } header: {
          SectionHeader("Kept out of your games")
        } footer: {
          Text("Players you blocked as a host can't join a game you host on this phone.")
        }
      }
      .navigationTitle("Safety")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
      .reportSheet($report)
    }
  }
}

/// Someone blocked: who, when, and a way to unblock them.
private struct BlockedRow: View {
  let name: String
  let detail: String?
  let date: Date
  let unblock: () -> Void

  var body: some View {
    HStack(spacing: Space.m) {
      VStack(alignment: .leading, spacing: Space.xxs) {
        Text(verbatim: name)
          .textRole(.body)
        Text(detail.map { "\($0) · \(date.formatted(date: .abbreviated, time: .omitted))" } ?? date.formatted(date: .abbreviated, time: .omitted))
          .textRole(.labelSmall)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: Space.s)
      Button("Unblock", action: unblock)
        .buttonStyle(.glass)
    }
    .swipeActions {
      Button("Unblock", systemImage: "hand.raised.slash", action: unblock)
    }
  }
}

#if DEBUG
#Preview("Safety") {
  SafetyView()
    .environment(Safety(defaults: nil))
}
#endif
