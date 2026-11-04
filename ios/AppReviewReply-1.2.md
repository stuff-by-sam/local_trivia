# Guideline 1.2 reply (rejection of 2026-10-17), for build 6

App Review asked for a screen recording **captured on a physical device**,
showing the terms, flagging and blocking. Record it on your iPhone with build
1.0 (6) — from TestFlight, or installed from Xcode (Control Center → Screen
Recording) — then upload it somewhere Apple can open (iCloud Drive "Anyone
with the link", or an unlisted video), and:

1. In App Store Connect, choose build 6 for version 1.0.
2. Reply in the Resolution Center with the text below, the recording
   attached.
3. Paste the same text into *App Review Information → Notes*, with the
   recording's link in place of the attachment (Notes takes text only).

The reply links to the terms on GitHub Pages, which go live only once
stuff-by-sam/local_trivia#11 is merged into `main`: merge it before you
reply.

## Shot list (about 2 minutes)

You need the iPhone and one other device with a browser on the same Wi-Fi (a
Mac is fine) to show a second player.

1. **Terms before anything.** Delete the app, install build 6, open it. The
   Terms of Use cover the screen; scroll through "No objectionable content.
   No abusive users." and "Reports". Tap **Agree and Continue**.
2. **How to Play.** A short tutorial follows the terms. Swipe through to its
   sixth page, **Play nice**, which shows how to report and block, then tap
   **Skip**. (How to Play — the **?** at the top left of the join screen —
   shows it again.)
3. **Terms again, and blocked lists.** Tap **Safety** (the hand, top left,
   beside the ?) to show Terms of Use, Report a Problem and the blocked lists.
   Tap Done.
4. **Filter.** Type an objectionable nickname: "That nickname isn't allowed"
   appears and Join stays off. Tap Host a Game, write a question with an
   objectionable word: it's flagged and stays out of play. Fix it.
5. **Host a game.** Start Hosting. On the Mac, open the address under the QR
   code, tick "I agree to the Terms of Use", join as a second player. Start the
   game.
6. **Flag content (player).** On a question, tap **•••** → **Report
   Question…**: pick a reason, tap **Send Report**, and Mail opens to
   report@local-trivia.com, written out. Send it. (Touching and holding the
   question does the same.)
7. **Block an abusive user (host).** Host menu → **Players** → swipe the
   Mac's player → **Block**. They're removed at once, a report opens, and their
   browser can't rejoin ("The host has blocked you from this game").
8. **Block (player).** To show the player side, join someone else's game from
   the iPhone (or a second iPhone): in the standings, touch and hold a name →
   **Block**: it becomes "Blocked player" at once, and a report opens. Then
   **•••** → **Block Host…** → **Block and Report**: the player leaves the game,
   the host's games disappear from the join screen, and a report opens.

## Reply

> Hello,
>
> Thank you for the review. Version 1.0 build 6 adds every precaution in
> guideline 1.2. The attached screen recording, captured on an iPhone, shows
> each one.
>
> **Terms of use (EULA).** Trivia has no registration or login, so the Terms
> of Use are shown when the app first opens, before anyone can host or join a
> game, and must be agreed to continue. They make clear there is no tolerance
> for objectionable content or abusive users. A short How to Play tutorial
> follows, which also shows players how to report and block. The terms are
> under Safety on the join screen, and at
> https://stuff-by-sam.github.io/local_trivia/terms.html, and people joining
> from a web browser must tick that they agree before they can join.
>
> **Filtering objectionable content.** Nicknames, game names, questions and
> answers are filtered for profanity, slurs and sexual terms. The host's phone
> turns objectionable nicknames away, a question that contains one can't be
> played, and a player's phone masks any objectionable word that still reaches
> it.
>
> **Flagging objectionable content.** In a game, the ••• menu reports the
> current question, a player or the game; touching and holding a question or
> a player's name does too. The host can report any player from the Players
> screen.
>
> **Blocking abusive users.** The host can block any player: they're removed
> from the game at once, and their phone or browser can't join that host's
> games again. A player can block another player, whose name is hidden from
> their screen at once, or block the game's host: they leave the game
> immediately, and that host's games are no longer listed. Every block
> notifies the developer, as a report.
>
> **Acting on reports within 24 hours.** Reports and blocks come to us by
> email at report@local-trivia.com, and we review every one within 24 hours.
> Trivia has no accounts and no servers: games run on the players' own devices
> over the local network, and nothing anyone types is stored once the game
> ends. So objectionable content and abusive users are removed on the spot by
> the people in the game, as above, and we act on each report by adding the
> objectionable words or names to the app's filter, so they can't be used in
> any game.
>
> Thank you.
