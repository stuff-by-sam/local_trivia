# App Store listing

What goes into App Store Connect for Trivia, in the order its pages ask for
it. Keep this in step with the app: a feature added or dropped changes the
description, and anything that sends data anywhere changes *App Privacy*.

## App Information

| Field | Value |
| --- | --- |
| Name (30) | Local Trivia |
| Subtitle (30) | Quiz night from your phone |
| Bundle ID | `com.stuffbysam.localtrivia` |
| SKU | `localtrivia-ios` |
| Primary language | English (U.S.) |
| Category | Games → Trivia, second subcategory Family |
| Secondary category | Entertainment |
| Content rights | Contains no third-party content |

The Home Screen shows **Trivia** (`CFBundleDisplayName`). If *Local Trivia* is
taken, *Local Trivia: Party Quiz* keeps the same words.

### Age rating

Every content question is **None**, and every yes/no is **No**:

- Parental controls, age assurance: No
- Unrestricted web access: No. The app serves its own web player to phones on
  the Wi-Fi, but doesn't browse the web.
- User-generated content: No. Nicknames and a host's questions go only to the
  phones in the same room, over the local network, and never to a server. The
  host can remove any player.
- Messaging and chat, advertising: No
- Contests: No (points on a leaderboard, no prizes)
- Gambling, simulated gambling: No

Expected rating: **4+**.

## Pricing and Availability

Free, in every territory. Under *iPhone and iPad Apps on Apple Silicon Macs*
and *Apple Vision Pro*, leave the app **off**: it hosts games over the local
network and reads QR codes with the camera, and neither has been tried there.

## App Privacy

- Privacy policy URL: https://stuff-by-sam.github.io/local_trivia/privacy.html
- Data collection: **No, we do not collect data from this app.**

That's accurate because nothing leaves the local network. Nicknames, answers
and questions go between the phones in a game, never to the developer or a
server, which is what Apple's definition of *collect* turns on. It matches
`PrivacyInfo.xcprivacy`, which declares no collected data and no tracking.

## Accessibility

Claim only what's been tested on a device:

| Feature | Supported | How it's covered |
| --- | --- | --- |
| VoiceOver | Yes | Every screen labelled; `AccessibilityUITests` audits each one |
| Voice Control | Check on a device first | Every control has a label, but nobody has played a game by voice yet |
| Larger Text | Yes | Every screen to AX5, audited for clipping |
| Dark Interface | Yes | The app is dark only |
| Differentiate Without Color Alone | Yes | Every answer has a letter and a shape as well as a colour |
| Sufficient Contrast | Yes | `ThemeTests` (WCAG AAA) and `GlassContrastUITests` (4.5:1 on glass) |
| Reduced Motion | Yes | Cursor stops blinking, shakes stilled, blurs become cross-fades |
| Captions, Audio Descriptions | Not applicable | No video or spoken audio |

## Version 1.0

**Promotional text** (170)

> Host a trivia night from your phone. Friends join on the same Wi-Fi with the
> app or any phone's browser. No accounts, no ads, no internet needed.

**Description** (4000)

> Trivia for the room you're in. One phone hosts, and everyone else joins on
> the same Wi-Fi, with the app or any phone's browser. No accounts, no sign-up,
> no internet needed.
>
> HOST FROM YOUR PHONE
> • Write a round in minutes: a question, four answers, tap the right one.
> Add categories and time limits, or import a CSV.
> • On iPhones with Apple Intelligence, name a topic and draft questions on
> the device, then review every answer before it goes in.
> • Set the scoring (points, time per question, shuffle and auto-advance),
> with a live preview of what an answer earns.
> • The host plays too.
>
> JOIN IN SECONDS
> • Games on your Wi-Fi show up by themselves. Type the four-digit PIN and
> you're in.
> • No app? Scan the host's QR code with any phone's camera to play in the
> browser.
> • Lock your phone or lose Wi-Fi mid-game, and you're back in your seat when
> you return.
>
> MADE FOR THE ROOM
> • Put the game on a TV with AirPlay or an HDMI adapter: the join code, each
> question and its clock, how the room voted, the standings and the podium.
> • No TV? Every phone gets the standings anyway.
> • Faster right answers score more. Standings after every question, and a
> podium at the end.
>
> MAKE IT YOURS
> • Ten themes, from phosphor green to holographic foil and chalkboard.
> • Five sets of answer markers, and an app icon to match every theme.
> • All of it free.
>
> PRIVATE BY DESIGN
> No accounts, ads, analytics or tracking. Games stay on your local network,
> between the phones in the room.
>
> Built for everyone, with VoiceOver, text sizes up to the largest, Increase
> Contrast, Reduce Motion and right-to-left layouts.

**Keywords** (100, commas, no spaces; words already in the name or subtitle
count without being repeated)

```
party,pub,game,multiplayer,family,friends,group,wifi,questions,answers,host,buzzer,team,classroom
```

| Field | Value |
| --- | --- |
| Support URL | https://stuff-by-sam.github.io/local_trivia/ |
| Marketing URL | (optional) the same |
| Version | 1.0 |
| Copyright | 2026 Sam Fox |

### Screenshots

`scripts/app-store-screenshots.sh` takes them on the 6.9" iPhone and 13" iPad
simulators App Store Connect asks for, from the debug build's screen fixtures,
into `build/screenshots/`. Upload the iPhone set under *6.9" Display* and the
iPad set under *13" Display*; App Store Connect scales them down for the
smaller sizes.

## App Review Information

- Sign-in required: **No**
- Contact: your name, phone and email (Apple only)

**Notes**

> Trivia is a party game played over the local network. The whole game can be
> tested on one device, because the host plays in their own game:
>
> 1. Tap Host a Game.
> 2. Tap Write a Question: type a question and four answers, and tap a
> letter to mark the right one. (On a device with Apple Intelligence, Draft
> with Apple Intelligence writes some instead.)
> 3. Tap Start Hosting and allow Local Network access, then Start Game.
>
> To add a second player, open the address shown under the host's QR code in
> any browser on the same Wi-Fi (a Mac works), or scan the QR code with a
> phone, and enter the PIN. A second device with the app finds the game on
> its join screen by itself.
>
> Local Network access is needed to find, host and join games. The camera is
> used only to scan a host's QR code, and is optional. The app has no
> accounts, and nothing leaves the local network.

## Export compliance

The app makes no encrypted connections of its own (games run over plain
WebSocket on the local network), so `ITSAppUsesNonExemptEncryption` is `NO`
in the target's build settings, and App Store Connect doesn't ask about it
with each build.
