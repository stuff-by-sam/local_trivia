# Trivia — design language

**Broadcast, in layered glass.** The game is a late-night broadcast terminal
on a phone: phosphor light on near-black, a monospaced voice that reports what
the game is doing, and four answer keys — circle, triangle, square, diamond —
that mean the same thing on every phone and on the TV. As in iOS 27's icons,
it's built in layers of glass: the backdrop at the bottom, cards of glass for
what the game says, the system's glass controls on top — and every letter and
mark the game shows made of Liquid Glass itself: the wordmark, the answer
markers, the figures, the verdict, the places, the dots. The brand is light
and voice; the glass is how it's held.

*Nocturnal · terse · luminous · exact · fair.*

Every value below is a token in the `DesignSystem` package
(`ios/DesignSystem`). A view that names a colour, size, radius, curve or
haptic directly is a bug; `DesignSystemLintTests` fails the build's tests if
one appears outside the package.

## Why this direction

Three directions were prototyped before settling on A (the prototypes were
removed once Broadcast was final):

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
| Controls (glass) | Toolbar items, buttons, the answer buttons, input fields, sheets, menus | System components first (`.glass`, `.glassProminent`, `.toolbar`, `Form`, `.sheet`). Custom glass for the answer buttons, PIN cells, the prompt field and the picker. |
| Content (glass) | The question, readouts, the join code card, name chips, status lines, badges, podium steps; on the TV, answer tiles, standings rows, name capsules | Real glass (`.panel()`, `.glassCard(in:)`), as clear or tinted as the screen's `GlassClarity`. Text on it is never glass. |
| Wordmark (glass letters) | "TRIVIA" and its block cursor | The system's glass, in the letters' own outlines (`Lettering`: the word set in Core Text and turned into a shape), tinted in the accent at 55 % over its own phosphor bloom. The cursor is a block of the same glass in the next character cell, as tall as the capitals and standing on their baseline. |
| Glass characters | Display type: rank, points, join code, verdict, medals' places, an answer's letter; on the TV, the masthead, "Standings", the PIN. Marks: every answer marker, the verdict and waiting symbols, the trophy, a standing's arrow, status dots. Shapes: the theme swatch's cursor, the app icons' shapes in Themes & Icons | The system's glass in the character's own outline, tinted in its colour (`GlassDepth.tint`: 90 % for a dot, 85 % beside a letter, 75 % in a card, 65 % at hero and TV sizes) over a bloom of it. Text is set in the font SwiftUI resolved for it (`Font.resolve(in:)`, `Lettering`): `GlassText`, and `GlassCounter` for a number that counts. Symbols are traced from the system's own with Vision, once, off the main actor (`SymbolOutlines`): `GlassSymbol`, `AnswerGlyph`; nothing of a symbol ships in the app. The real text or symbol still lays each one out, hidden, so it keeps its size, baseline, Dynamic Type and shrink-to-fit. Each character's glass has its own container, so it never melts into the glass it sits on. A traced symbol is drawn glass for the moment before its trace is in; everything is flat colour under Increase Contrast. Only for display type and marks — never body text, a question, an answer or what the player types. |
| Backdrop (drawn) | Ink, the glow, the theme's texture | What the glass refracts. Colour lives here. |

**Clarity.** Menus — the join screen, the lobby, Themes & Icons, the TV while
people arrive — use clear glass (`GlassClarity.clear`): their content is short
and high-contrast, so the backdrop shows through. The game — the question,
results, standings, the podium — uses glass tinted toward the ink
(`.tinted`), so it's read at a glance whatever the backdrop is doing.
`RootView` sets it by phase. Under Increase Contrast every card is the
tinted, frosted kind, with a hairline edge.

Tint appears in exactly six places: the primary action, the chosen answer,
the lit PIN cell, the low-time clock, the viewer's own name chip, and the
accent on headings/cursor.

## Colour

The app is dark-only (`UIUserInterfaceStyle = Dark`). It's a room game read
at night, next to a dark TV board, and the brand *is* light on black. Dark
appearance is designed for Standard and Increased Contrast; Reduce
Transparency changes the backdrop and panels.

Roles resolve from the environment (`Palette`, theme × contrast ×
transparency). Use `.foregroundStyle(.danger)` or `palette.danger`, never a
hex. (The accent role is spelled `.themeAccent`: Xcode generates `.accent`
from the asset catalog's `AccentColor`.)

| Role | Standard | Increased contrast | Use |
|---|---|---|---|
| `themeAccent` | theme accent (Phosphor `#56FF8A`) | same | primary action tint, cursor, headings, selection |
| `onAccent` | `#04080A` | same | text/glyphs on any lit or tinted surface |
| `ink` | theme ink (Phosphor `#04080A`) | same | the ground under everything |
| `primary` / `secondary` text | system `.primary` / `.secondary` | system (raised) | content / labels. **`.tertiary` is never used for text a player needs.** |
| `panel` | white 4 % | white 10 % | a drawn fill, where glass can't go |
| `panelStroke` | white 12 % | white 40 % | a card's edge under Increase Contrast; swatch and icon tile borders |
| `hairline` | white 8 % | white 30 % | row dividers |
| `slot` | white 14 % | white 40 % | an empty PIN cell's underscore |
| `success` | `#56FF8A` | same | correct, online — always with ✓ or a dot and a word |
| `danger` | `#FF6A6A` | same | wrong, errors, low time — always with ✕, ⚠ or a word |
| `warning` | `#FFD60A` | same | reconnecting, notices |
| `neutral` | `#9AA8BA` | same | missed / no answer |
| `medal1/2/3` | `#F5C542` / `#C7CED8` / `#D98E5B` | same | podium and ranks 1–3, always with "1st/2nd/3rd" |

**The answer set** is not a theme colour, and its colours and letters never
change: A `#56FF8A`, B `#55E6FF`, C `#FFB347`, D `#FF6AD5` — the web game's
`PAL`. Answer colours appear only on answers. (Medals were green and cyan;
now gold, silver, bronze, so "third place" no longer reads as "B".)

**The shapes** beside the letters are the phone's `AnswerMarkers`: Classic's
circle, triangle, square and diamond (the web game's), or another set the player picks —
Suits, Elements, Sky, Critters. A set dresses its phone and the TV that phone
drives, and nothing else; the web game keeps Classic. Every set's four shapes
differ in silhouette, not just colour, and have their own names for VoiceOver.
A key is still colour + shape + letter, so no answer depends on colour alone.

**Themes** (picked in Themes & Icons) change `accent`, `ink` and the backdrop texture
only. They never touch the answer colours, the shapes or the status colours. `ThemeTests` holds
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
| `title` | Pro | largeTitle | bold | as written | the player's own name in the lobby |
| `headline` | Pro | headline | semibold | as written | the game's name in the picker |
| `detail` | Pro | footnote | regular | sentence | taglines, explanations |
| `shout` | Mono | title3 | heavy | UPPER, 4 | verdicts, "Hold tight" |
| `action` | Mono | headline | bold | UPPER, 1.4 | primary/secondary action labels |
| `status` | Mono | footnote | semibold | UPPER, 1.4 | status lines, toolbar chips |
| `label` | Mono | caption | semibold | UPPER, 1.4 | field and readout labels |
| `labelSmall` | Mono | caption2 | semibold | UPPER, 1.4 | tertiary metadata (never essential) |
| `figure` | Mono | body | semibold | — | readout values, scores |
| `figureSmall` | Mono | caption | medium | — | addresses, podium scores |
| `display(.hero / .points / .pinLarge / .pin / .cell)` | Mono | 100 / 58 / 64 / 44 / 34 pt, relative to largeTitle, max 1.35× | heavy (points, cells: bold) | PIN only: 8 / 6 | rank, points, join code, PIN cells |

The TV board has its own fixed ramp (`TVRole`, with `TVMetrics` for layout) on its 1920×1080 canvas —
Dynamic Type doesn't reach a TV.

**At accessibility sizes**, content grows and bars don't. A screen whose
content no longer fits scrolls (`.scrollsWhenCrowded()`) rather than
squeezing text until it's cut off; readouts, leaderboard rows, round rows and
the join card stack instead of sharing a line. What's pinned — the action bar,
the host's next move, the undo toast — stops at AX1 (`Size.barTypeLimit`),
as the system's own bars do, since at AX5 it would cover the content it's for.
Toolbar readouts stay at the bar's size. Both show the Large Content Viewer
on a long press.

## Space, shape

**Spacing** — 4-pt base. `Space.xxs 2 · xs 4 · s 8 · m 12 · l 16 · xl 24 ·
xxl 32 · xxxl 48`. Screen margin `Space.l` (16), matching system list insets.
Stack gaps: related `s`, grouped `m`, sections `xl`.

**Insets** — text never crowds the sides of the shape it sits in. It's
`Space.inset` (20) in from the sides of an answer, a field, a readout row, a
card or a toast, clear of the corner's curve; `Space.capsuleInset` (16) in a
name chip; `Space.keyInset` (10) in an answer's key. An action button's title
keeps `Space.s` inside the system's own inset, and a toolbar readout (the
player's name, `Q 03/12`, the clock) keeps `Space.m` inside the glass capsule
the system draws around it. On the TV, `TVMetrics.inset`
(48) for tiles and rows, `TVMetrics.nameInset` (36) for name tiles.

**Radius** — concentric. `Radius.control 20` (answers, fields, PIN cells),
`Radius.panel 24` (readouts, cards), capsule for chips and buttons (a name
chip or undo toast that wraps becomes a `Radius.control` rectangle). A shape
inside another takes `Radius.concentric(in:inset:)` — its container's radius
minus the inset, minimum 8 — so the answer key inside an answer button is
`20 − 20 = 0 → 8`, and the QR code on a card is `24 − 20 = 4 → 8`. Computed, not
`ConcentricRectangle`: the same shapes also sit outside any container.

**Targets** — 44×44 pt minimum everywhere (`Size.target`). Answer buttons
are ≥ 60 pt tall (`Size.answer`).

**Glow** — the phosphor bloom behind a lit figure is `.glow(_:)`: `.edge` 6,
`.figure` 10, `.hero` 14, `.medal` 18, `.tv` 30. Off under Increase Contrast.

**Glass depth** — how big a glass character is (`GlassDepth`): its tint, its
bloom's radius (unless it takes a `Glow`), and the room its glass's shadow
needs (4 × the bloom). `.dot` 90 % / 3 (status dots), `.mark` 85 % / 1 (keys,
swatches, arrows), `.figure` 75 % / 2.5 (the join code in a card, the
verdict, places, the brand mark), `.hero` 65 % / 5 (rank, points, badge
symbols, trophy), `.tv` 65 % / 10.

## Materials

| Material | Where | Reduce Transparency | Increase Contrast |
|---|---|---|---|
| `Glass.regular` | toolbar, buttons, fields, dimmed answers | system frosted | system |
| `.regular.interactive()` | custom touchable glass (answers, PIN, picker) | system | system |
| `.regular.tint(answer, 9 %)` | an open answer | system | 18 % + answer-colour stroke |
| `.glassProminent` in the answer's colour at 80 % | the chosen answer — the system's lit glass, which sets its label on the glass; custom tinted glass tints the label inside it too, and took the lit answer's ink to 3:1 | system | 90 % |
| `.glassProminent` + `accent` | primary action | system | system |
| `Glass.clear` | content cards on menus (`GlassClarity.clear`) | system frosted | tinted instead |
| `.regular.tint(ink, 50 %)` | content cards in the game (`.tinted`): the question, readouts, status lines | system frosted | 70 % + `panelStroke` edge |
| `.regular.tint(colour, 20 %)` | podium steps (medal), the viewer's own name chip (accent), badges (verdict); on the TV, answer tiles (answer, 16 %; the right one 90 %) | system frosted | 30 % |
| `.regular.tint(accent, 55 %)` in the letters' outlines | the wordmark and its cursor, over a bloom of the accent at the `Glow` radius | system frosted | solid accent, no bloom |
| `.regular.tint(colour, 65–90 %)` in a character's outline | every other glass character (`GlassDepth`), over a bloom of its colour | system frosted | the text or symbol in flat colour |
| `Glass.clear` in each shape's outline | the app icons in Themes & Icons, over each shape's own paint | system frosted | the paint alone |
| Backdrop (drawn) | behind every screen | glow only: no texture, no tilt | glow only: no texture, no vignette |

An answer's key is glass characters on a drawn cap with a lit edge
(`glassRim`), not the system's glass: the cap sits on glass already, and a
third layer of glass that small only blurs. On a lit answer it's plain dark
ink, which reads best there; so is the chosen answer's checkmark.

Glass inside a system `Menu`'s label doesn't draw, so the game picker's
status mark is drawn over the menu, in the same place (`pickerMark(_:)`).
Sheets use the system sheet material — they don't draw the backdrop. The
one exception is Themes & Icons, whose job is showing a theme on its backdrop:
its rows are clear glass over it.

Lit glass glows up through a sheet's glass — even hidden, it still does. So
while one of the host's sheets is up, the host's action button under it is
unlit (secondary) as well as hidden; it keeps its size, so nothing moves when
the sheet goes.

A bar over scrolling content has a hard edge (`scrollEdgeEffectStyle(.hard)`)
where text would otherwise show through the glass of its buttons: the host's
setup and drafting sheets, and the join screen on a phone while the keyboard
is up. Everywhere else it's soft, so the backdrop runs to the bottom.

The answer-to-verdict morph needs one `GlassEffectContainer` around the
in-game screens. The join screen sits outside it: on iOS 27.0, glass buttons
in a `safeAreaBar` inside a container don't receive taps.

## Motion

Physics only: every curve is a spring token, every animation is
interruptible, and nothing waits for decoration but one beat: at the reveal
the points start counting `Motion.pointsDelay` (0.22 s) after the verdict
starts to land, so the verdict is read first. Under Reduce Motion every token
becomes `reduced` (a 0.2 s smooth cross-fade), shakes stop, blur
transitions become opacity, and the points don't wait.

| Token | Spring | Use |
|---|---|---|
| `Motion.snap` | `.snappy(duration: 0.2)` | control state: lock, key pick, digit in |
| `Motion.settle` | `.smooth(duration: 0.35)` | status text, small layout changes |
| `Motion.screen` | `.smooth(duration: 0.5)` | phase-to-phase screen change (blurReplace) |
| `Motion.mood` | `.smooth(duration: 0.9)` | backdrop glow changing hue |
| `Motion.pop` | `.spring(duration: 0.35, bounce: 0.45)` | verdict badge, rank on the podium |
| `Motion.count` | `.smooth(duration: 0.6)` — no bounce, so the count never passes the score | points counting up in glass (`GlassCounter`), `pointsDelay` (0.22 s) after the verdict |
| `Motion.breathe` | `.smooth(duration: 0.8)`, back and forth | a glass mark waiting: the hourglass, a connecting dot (`.glassPulse`); steady under Reduce Motion |
| `.glassBounce(trigger:)` | spring keyframes 1 → 1.2 → 0.94 → 1 | a glass verdict or trophy landing — SF Symbols' bounce doesn't reach glass; still under Reduce Motion |
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

SF Symbols for every icon in the app — no icon is a text glyph (a standing's
move is `arrowtriangle.up.fill` / `.down.fill` and its number, not `▲2`).
Weight follows the adjacent text's weight; scale `.medium`, `.small` inside
keys. Monochrome by default. The answer markers — every set's, from
`circle.fill` to `bird.fill` — are Liquid Glass in their answer colour, cut to
the symbol's traced outline (`AnswerGlyph`), as are the verdict, the trophy,
the waiting hourglass and a standing's arrows (`GlassSymbol`). Direction uses
`.forward`/`.backward` variants so RTL mirrors; the wordmark and the answer
keys (`▲ B`) never mirror. Effects: a glass verdict or first place hops
(`.glassBounce`) and a waiting one breathes (`.glassPulse`) — SF Symbols' own
effects don't reach glass — and a checkmark `.appear`s; all quieted by Reduce
Motion.

The app icons are the exception: Apple's terms don't allow SF Symbols, or
look-alikes, in app icons or logos, so the icons' shapes are their own
drawings.

## Components

Every component has a preview per state, plus Dynamic Type xSmall and AX5,
Increase Contrast, Reduce Transparency, Reduce Motion, RTL, long and empty
content (`DesignSystem/Sources/DesignSystem/Previews/ComponentPreviews.swift`).
Every screen has previews of its main states too, at the foot of its file,
built from in-memory models (`Design/ScreenStates.swift`): nothing in them
touches the network.

| Component | States |
|---|---|
| `ActionButton` (primary / secondary), `ActionBar` | enabled, pressed, disabled, loading; optional tap haptic |
| `AnswerButton` | open, chosen, dimmed (another chosen, or time's up) |
| `AnswerKey` | normal, inverted (on a lit surface) |
| `PINCells` | empty, next (lit edge + cursor), filled, rejected (`.rejectionShake`) |
| `PromptField` (`> name`) | empty, focused, filled |
| `FieldMessage` | error, notice, hint |
| `PickerRow` | searching, online, connecting, unreachable |
| `LabeledField`, `SectionHeader`, `DividerLabel` | — |
| `Readout` / `ReadoutRow`, `.panel()` | inline, stacked (long value or AX size), empty; IC; RT |
| `.scrollsWhenCrowded()` | centred when it fits, scrolling when it doesn't |
| `StatusLine` | waiting (cursor), steady; on a glass capsule (a rounded rectangle at AX sizes) |
| `StatusDot` | online, connecting (breathes), failed (breathes), idle; a glass bead |
| `Wordmark`, `AnswerSetMark` | screen, showcase, tv (the TV's idle board, previewed there) |
| `RankFigure` | medal 1/2/3, other, unranked; compact |
| `PodiumStep` | 1st/2nd/3rd, the player's own |
| `Badge` | verdict (tinted in its colour), waiting |
| `.panel()`, `.glassCard(in:tint:)` | clear, tinted, coloured; IC; RT |
| `GlassText`, `GlassCounter`, `GlassSymbol`, `AnswerGlyph`, `glassRim` | each `GlassDepth`; with a `Glow`; IC (flat) |
| `NameChips` (`FlowLayout`) | names, the viewer's own (accent glass), a long name wrapping; read as one list |
| `UndoToast` (`.undoToast`) | shown, counting down, undone |
| `ThemeSwatch`, `IconArtwork`, `MarkerSwatch` | every theme, icon and marker set; shown |
| `Backdrop` | moods idle/question/correct/wrong/missed/celebrate × 10 textures × RT/IC/RM |
| Empty / loading / error | `ContentUnavailableView`, `StatusLine`, `FieldMessage` |

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

## Waiting

Every wait says what's happening, in the game's voice, and has a way on. No
spinner stands in for a button that can't be pressed.

| Wait | What it shows | The way on |
|---|---|---|
| Finding games | A spinner in the picker, `JOIN THE HOST'S WI-FI`; after 6 s, why, and the QR code | Scan QR Code, Local Network Settings |
| Joining | The Join button's spinner; after 5 s, *The game didn't answer. Try again.* | Join again |
| Rejoining | `REJOINING YOUR GAME_` (or *Host unreachable, retrying*) | Start Over |
| Starting to host | The Start Hosting button's spinner; the reason, if it fails | Start Hosting again |
| Drafting | *Writing and checking 3 of 10…* under the drafts so far; VoiceOver hears when it's done | Stop Drafting (keeps what's drafted), Add, Cancel |
| Between moments | A status capsule ending in the cursor; the hourglass breathing while spectating | The host's next move |
| Reconnecting | The toolbar's *Reconnecting*, its dot breathing | Leave, once the host has gone quiet |

**Glass at launch.** Every symbol the game makes of glass is traced in the
background as the app starts — the worn markers first, then the reveal's —
and kept on the device, so after the first launch each draws as glass from
its first frame. One shown before its trace is in (the first launch only) is
drawn glass until then, and cross-fades; text is set as glass at once.

## Surfaces

| Surface | Treatment |
|---|---|
| App icon ×10 | Icon Composer: the answer set on ink, each shape its own glass layer (four groups, front to back circle, triangle, square, diamond), 272 pt across on a 2 × 2 grid centred at 320/704 of 1024. Checked with iOS 27's renderer (`ictool --design-generation 27`) in Default, Dark, Clear Light/Dark, Tinted Light/Dark. `IconArtwork` draws the same layers in the app. |
| Launch | Plain black (`LaunchBackground`), straight into the game — no overlay |
| TV (external display) | `BigScreenView`, same tokens and the same glass at `TVType` sizes; clear while people arrive, tinted once the game's on |
| Sheets, alerts, menus | System, with `accent` tint |
| Empty / loading / error | Content-layer voice over system components |
| Widgets, Live Activities, notifications | **None, by decision.** A phone-hosted game has no server to update them, and nothing to show between games. |
