# Trivia — design language

**Broadcast.** The game is a late-night broadcast terminal on a phone:
phosphor light on near-black, a monospaced voice that reports what the game
is doing, and four answer keys — circle, triangle, square, diamond — that mean
the same thing on every phone and on the TV. Everything you touch is the
system's own Liquid Glass; everything the game *says* lives in the content
under it. The brand is light and voice, not chrome.

*Nocturnal · terse · luminous · exact · fair.*

Every value below is a token in the `DesignSystem` package
(`ios/DesignSystem`). A view that names a colour, size, radius, curve or
haptic directly is a bug; `DesignSystemLintTests` fails the build's tests if
one appears outside the package.

## Why this direction

Three directions were prototyped as named previews in
`LocalTrivia/Design/Explorations.swift` (launch with `-explore a.join` etc.):

| | A · Broadcast | B · Studio | C · Game Show |
|---|---|---|---|
| Idea | The terminal voice in content; system chrome | Pure system: SF Pro, grouped lists, no texture | Filled answer tiles, rounded type, colour everywhere |
| Familiarity | Same language as the TV board and the web presenter | Familiar, but indistinguishable from any utility | Familiar from other quiz games, not from this one |
| Two-layer model | Brand in content, controls stock | No brand layer at all | Brand fights the glass: four saturated slabs under it |
| Legibility | Text on ink ≥ 6:1; lit answer takes dark ink | High | White on the orange and green tiles is ~1.9:1 |
| Delight | The phosphor glow, the cursor, the answer glass flowing into the verdict | None | Loud, and loud on every screen, including the question |

**A, with B's discipline.** From B it takes the system toolbar, system
sheets, forms and bottom action bars; from A, everything the game says. C is
cut: tint is for selection and primary actions, and C tints everything.

## Layers

| Layer | What's in it | Rule |
|---|---|---|
| UI (glass) | Toolbar items, buttons, the answer buttons, input fields, sheets, menus | System components first (`.glass`, `.glassProminent`, `.toolbar`, `Form`, `.sheet`). Custom glass only for the answer buttons, PIN cells and the prompt field — each serves a top task — and never on content. |
| Content (brand) | Backdrop, wordmark, question text, readouts, figures, status lines, podium, the TV board | Drawn, not glassed. Colour, type and motion from the tokens below. |

Tint appears in exactly five places: the primary action, the chosen answer,
the lit PIN cell, the low-time clock, and the accent on headings/cursor.

## Colour

The app is dark-only (`UIUserInterfaceStyle = Dark`). It's a room game read
at night, next to a dark TV board, and the brand *is* light on black. Dark
appearance is designed for Standard and Increased Contrast; Reduce
Transparency changes the backdrop and panels.

Roles resolve from the environment (`Palette`, theme × contrast ×
transparency). Use `.foregroundStyle(.danger)`, not a hex.

| Role | Standard | Increased contrast | Use |
|---|---|---|---|
| `accent` | theme accent (Phosphor `#56FF8A`) | same | primary action tint, cursor, headings, selection |
| `onAccent` | `#04080A` | same | text/glyphs on any lit or tinted surface |
| `ink` | theme ink (Phosphor `#04080A`) | same | the ground under everything |
| `primary` / `secondary` text | system `.primary` / `.secondary` | system (raised) | content / labels. **`.tertiary` is never used for text a player needs.** |
| `panel` | white 4 % | white 10 % | readout and card fills |
| `panelStroke` | white 12 % | white 40 % | readout and card borders |
| `hairline` | white 8 % | white 30 % | row dividers |
| `success` | `#56FF8A` | same | correct, online — always with ✓ or a dot and a word |
| `danger` | `#FF6A6A` | same | wrong, errors, low time — always with ✕, ⚠ or a word |
| `warning` | `#FFD60A` | same | reconnecting, notices |
| `neutral` | `#9AA8BA` | same | missed / no answer |
| `medal1/2/3` | `#F5C542` / `#C7CED8` / `#D98E5B` | same | podium and ranks 1–3, always with "1st/2nd/3rd" |

**The answer set** is not a theme colour and never changes: A `#56FF8A` circle,
B `#55E6FF` triangle, C `#FFB347` square, D `#FF6AD5` diamond — the web game's
`PAL`. Answer colours appear only on answers. (Medals were green and cyan;
now gold, silver, bronze, so "third place" no longer reads as "B".)

**Themes** (sold in the shop) change `accent`, `ink` and the backdrop texture
only. They never touch the answer set or status colours. `ThemeTests` holds
each theme's accent on its ink, and `onAccent` on its accent, to 7:1.

## Type

Two voices. SF Pro carries content (questions, answers, names). SF Mono is
the game talking (labels, figures, the clock, status). Every role maps to a
Dynamic Type text style; display figures scale with `@ScaledMetric` and cap.

| Role | Face | Text style | Weight | Case / tracking | Use |
|---|---|---|---|---|---|
| `question` | Pro | largeTitle → title → title2 → title3 by length | bold/semibold | sentence | the question |
| `answer` | Pro | title3 → body → callout by longest option | semibold (chosen: bold) | as written | answer text |
| `body` | Pro | body | regular | sentence | explanations |
| `bodyEmphasis` | Pro | body | semibold | sentence | names, row titles |
| `shout` | Mono | title3 | heavy | UPPER, 4 | verdicts, "Hold tight" |
| `action` | Mono | headline | bold | UPPER, 1.4 | primary/secondary action labels |
| `status` | Mono | footnote | semibold | UPPER, 1.4 | status lines, toolbar chips |
| `label` | Mono | caption | semibold | UPPER, 1.4 | field and readout labels |
| `labelSmall` | Mono | caption2 | semibold | UPPER, 1.4 | tertiary metadata (never essential) |
| `figure` | Mono | body | semibold | — | readout values, scores |
| `display(.hero/.large/.medium/.cell)` | Mono | 100 / 64 / 44 / 34 pt, relative to largeTitle, max 1.35× | heavy/bold | — | rank, points, PIN, PIN cells |

The TV board has its own fixed ramp (`TVType`) on its 1920×1080 canvas —
Dynamic Type doesn't reach a TV.

## Space, shape

**Spacing** — 4-pt base. `Space.xxs 2 · xs 4 · s 8 · m 12 · l 16 · xl 24 ·
xxl 32 · xxxl 48`. Screen margin `Space.l` (16), matching system list insets.
Stack gaps: related `s`, grouped `m`, sections `xl`.

**Radius** — concentric. `Radius.control 20` (answers, fields, PIN cells),
`Radius.panel 24` (readouts, cards), capsule for chips and buttons. A shape
inside another uses `ConcentricRectangle` against its container, minimum 8, so
the answer key inside an answer button is `20 − 14 = 6 → 8`.

**Targets** — 44×44 pt minimum everywhere (`Space.target`). Answer buttons
are ≥ 60 pt tall.

## Materials

| Material | Where | Reduce Transparency | Increase Contrast |
|---|---|---|---|
| `Glass.regular` | toolbar, buttons, fields, dimmed answers | system frosted | system |
| `.regular.interactive()` | custom touchable glass (answers, PIN, picker) | system | system |
| `.regular.tint(answer, 9 %)` | an open answer | system | 18 % + answer-colour stroke |
| `.regular.tint(answer, 80 %)` | the chosen answer | system | 90 % |
| `.glassProminent` + `accent` | primary action | system | system |
| Panel (drawn) | readouts, join code card | `ink` mixed 8 % white, opaque | `panel`/`panelStroke` IC values |
| Backdrop (drawn) | behind every screen | glow only: no texture, no tilt | glow only: no texture, no vignette |

Sheets use the system sheet material — they don't draw the backdrop.

## Motion

Physics only: every curve is a spring token, every animation is
interruptible, nothing waits for decoration. Under Reduce Motion every token
becomes `reduced` (a 0.2 s smooth cross-fade), shakes stop, and blur
transitions become opacity.

| Token | Spring | Use |
|---|---|---|
| `Motion.snap` | `.snappy(duration: 0.2)` | control state: lock, key pick, digit in |
| `Motion.settle` | `.smooth(duration: 0.35)` | status text, small layout changes |
| `Motion.screen` | `.smooth(duration: 0.5)` | phase-to-phase screen change (blurReplace) |
| `Motion.mood` | `.smooth(duration: 0.9)` | backdrop glow changing hue |
| `Motion.pop` | `.spring(duration: 0.35, bounce: 0.45)` | verdict badge, rank on the podium |
| `Motion.count` | `.snappy(duration: 0.6)` | points counting up |
| `Motion.reject` | keyframes −14 → 12 → −8 → 0 over 0.3 s | wrong PIN / taken name (off under Reduce Motion) |

Signature motion: the chosen answer's glass flows into the verdict badge
(`glassEffectID`). It's the one morph kept, because it carries meaning —
*your answer became this result*.

## Haptics

Only through `Haptic`; one per event, never on scroll or incidental change.

| `Haptic` | Feedback | Event |
|---|---|---|
| `.lock` | impact medium, 0.9 | answer tapped |
| `.correct` / `.wrong` / `.missed` | success / error / warning | reveal |
| `.joined` | success | into the lobby |
| `.questionStart` | start | question appears |
| `.rejected` | error | wrong PIN, taken name |
| `.action` | impact medium | host taps the action bar |
| `.found` | success | QR code read |

## Symbols

SF Symbols only. Weight follows the adjacent text's weight; scale `.medium`,
`.small` inside keys. Monochrome by default; the answer shapes (`circle.fill`,
`triangle.fill`, `square.fill`, `diamond.fill`) are monochrome in their answer
colour. Direction uses `.forward`/`.backward` variants so RTL mirrors. Effects:
`.bounce` for a verdict or first place, `.pulse` for waiting, `.appear` for a
checkmark — all system, all quieted by Reduce Motion.

## Components

Every component has a preview per state, plus Dynamic Type xSmall and AX5,
Increase Contrast, Reduce Transparency, Reduce Motion, RTL, long and empty
content (`DesignSystem/Sources/DesignSystem/Previews`).

| Component | States |
|---|---|
| `ActionButton` (primary / secondary) | enabled, pressed, disabled, loading |
| `AnswerButton` | open, chosen, dimmed, closed (time's up) |
| `AnswerKey` | normal, inverted (on a lit surface) |
| `PINCells` | empty, next (lit edge + cursor), filled, rejected (shake) |
| `PromptField` (`> name`) | empty, focused, filled, error |
| `Readout` / `ReadoutRow` | inline, stacked (long value or AX size), empty |
| `Panel` | standard, IC, RT |
| `StatusLine` | waiting (cursor), steady (Reduce Motion) |
| `StatusDot` | online, connecting (pulse), failed |
| `RankFigure` | medal 1/2/3, other, unranked |
| `UndoToast` | shown, counting down, undone |
| `Backdrop` | moods idle/question/correct/wrong/missed/celebrate × 10 textures × RT/IC/RM |
| Empty / loading / error | `ContentUnavailableView` with a status-line voice |

## Voice

- **The game reports; it doesn't chat.** Status lines are short, present
  tense, uppercase mono, and end in the cursor when waiting:
  `WAITING FOR HOST_`, `LOCKED IN · 3 OF 6 ANSWERED`.
- **Content is verbatim.** Questions, answers and names render exactly as
  written (`Text(verbatim:)`), never as Markdown or a localization key.
- **Buttons are verbs**, title case: *Join Game*, *Start Hosting*, *Next
  Question*.
- **Errors say what happened and what to do**, in one line, no blame:
  *Wrong PIN. Check the host's screen.*
- **No exclamation marks** except *Correct!* in the VoiceOver announcement.
- **Undo, not "Are you sure?"** Confirmation is kept only for Stop Hosting,
  which ends the game on every phone and can't be undone.

## Surfaces

| Surface | Treatment |
|---|---|
| App icon ×10 | Icon Composer, answer set on ink; checked in Default, Dark, Clear Light/Dark, Tinted Light/Dark |
| Launch | Plain black (`LaunchBackground`), straight into the game — no overlay |
| TV (external display) | `BigScreenView`, same tokens at `TVType` sizes |
| Sheets, alerts, menus | System, with `accent` tint |
| Empty / loading / error | Content-layer voice over system components |
| Widgets, Live Activities, notifications | **None, by decision.** A phone-hosted game has no server to update them, and nothing to show between games. |
