# Rations

[![Release](https://img.shields.io/github/v/release/headconnect/rations)](https://github.com/headconnect/rations/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

macOS menu bar app showing your Claude, Codex, GitHub Copilot and Google
Antigravity plan usage with reset countdowns: the 5-hour session and weekly
windows for Claude, Codex and Antigravity, the monthly premium-request quota for
Copilot. It reads the same numbers as the usage pages on claude.ai, chatgpt.com
and github.com, and Antigravity's `/usage`.

Menu bar: `A ▤ 12%/4%  O ▤ 77%/47%  G ▤ 18%`, one entry per signed-in account,
tagged by vendor unless you rename it (Anthropic, OpenAI, GitHub, Y for Antigravity): a mini bar per
limit and the percentages, short-term window first (session/weekly). Bars turn
orange at 70 % and red at 90 %.

![Menu bar with three accounts, the popover showing Claude, Codex and Copilot usage with the Codex session bar orange past 70 %, a fourth account waiting to sign in, and the settings window alongside](docs/images/rations-screenshot-2.1.1.png)

## Requirements

- macOS 14 or later
- Any of: a Claude Pro/Max/Team account, a ChatGPT account with Codex, a GitHub account with Copilot, a Google account with Antigravity

## Install

Download the latest DMG from [Releases](https://github.com/headconnect/rations/releases/latest),
open it, and drag Rations into the Applications folder shown next to it. It's
signed and notarized, so Gatekeeper lets it run without extra steps. Then open
it from Applications or Spotlight; it appears in the menu bar, not the Dock.

Or with [Homebrew](https://brew.sh):

```sh
brew install headconnect/tap/rations
```

Tick "Launch at login" in the [settings](#settings) to keep it running.

### Build from source

Needs a Swift 5.10+ toolchain (Xcode Command Line Tools are enough):

```sh
make install   # builds "build/Rations.app" and copies it to /Applications
open "/Applications/Rations.app"
```

`make run` builds and launches without installing.

## Sign in

Add an account first — in the [settings](#settings), or from the popover while
it is empty — then sign in to it. Several accounts of the same provider are
fine; each gets its own menu bar tag. Tokens for all of them live in a single
login keychain item (service `no.enso.rations`, account `accounts`) and are
refreshed automatically. The app was called headroom up to 2.0 and Range
Anxiety in 2.1; the first launch under this name moves the vault, settings and
account list over from whichever it finds (or the 1.x per-provider items) and
then deletes them. Release builds share the old signing identity, so that is
silent; a locally built app prompts once per item.

**Claude.** Click *Sign in to Claude*. Your browser opens claude.ai; after you
authorize, Anthropic shows a code and tells you to paste it into Claude Code.
Paste it into Rations instead and press *Continue*.

**Codex.** Click *Sign in to Codex*. Your browser opens auth.openai.com and
redirects back to `http://localhost:1455` when done. Nothing to paste.

**Copilot.** Click *Sign in to Copilot*. Rations shows an 8-character code
(with a copy button; it is also put on your clipboard) and opens
github.com/login/device. Enter the code there; Rations picks up the token by
itself.

**Antigravity.** Needs Antigravity or its `agy` CLI installed (see [How it
works](#how-it-works)). Click *Sign in to Antigravity*. Your browser opens
Google's sign-in and redirects back to `http://localhost:51121` when done.
Nothing to paste.

**Privately.** The arrow next to a sign-in button runs the same flow in a window
that shares no cookies with your browser, so a second account of a provider is
not signed straight back in as the first. Only one account can be signing in at
a time; *Cancel* in the popover ends it, closing the window does not.

Sign out with the door icon next to an account. Signing out deletes its stored
tokens, and so does removing the account.

## Settings

The gear at the bottom of the popover opens the settings window; the plus next
to it adds an account without going there. The window has a tab each for
Accounts, Menu Bar, General, Usage Hub and About (version and GitHub links).

**Accounts.** The accounts in menu bar order on the left; drag to reorder, the
plus below adds one. On the right, the selected account: sign in or out, then
its label: a tag of up to 3 characters (emoji count as one, empty falls back
to the provider's letter), an optional image shown instead, and an optional
name such as "Office". *Customise menu bar* gives the account its own copy of
the Menu Bar tab's toggles; turning it off follows those again. *Remove
Account…* asks first, then signs out and forgets the tokens.

*Gauges* decides what reaches the menu bar. *Automatic* shows the provider's
main limits, as described below. *Custom* lets you choose them: a list of
gauges and spacers in order, starting from today's automatic limits. Each gauge
is its own menu bar entry with up to two limits picked from what the account
reports, e.g. Antigravity's Claude and GPT 5-hour and weekly limits as `YC`, or
Claude's Fable allowance next to the usual `A`. *Add* adds a gauge or a spacer;
the ⋯ menu moves or removes one, and the last gauge stays. A picked limit the
provider stops reporting is kept and shows `–` until it is back. Custom gauges
ignore the session/weekly toggles; their countdowns follow the session or
weekly option by the limit's length.

The first gauge shows the account's tag or icon from *Label* (its box says
*Inherited*). Later gauges and spacers have their own, edited in the box at the
start of the row: a tag of up to 3 characters or, switched to *Icon*, an image
you click to change. An empty gauge tag uses the account's; a spacer's tag is
`|` by default, and empty leaves a plain gap. Put a spacer last to separate the
account from the next.

**Menu Bar.** Defaults for accounts without their own. *Bars* and *Percentages*
choose how each account is shown; at least one stays on. *Session* and *Weekly*
choose which limits are shown, for providers that have both. Copilot has a
single quota and always shows it.

*At 100%, show time until reset* replaces an exhausted percentage with a local
countdown, such as `04:37` or `3d 17:29`. Session and weekly countdowns are
independent and off by default; the weekly/monthly option also covers Copilot.
Account customisation can override them. Countdowns update every minute without
extra API requests. Without a reset time the percentage stays; after the reset,
`00:00` stays until fresh usage arrives.

Claude's popover also shows *Weekly · Fable* when Anthropic reports that
allowance. Its percentage measures the Fable allowance itself; 100% means that
allowance is exhausted. It appears in the menu bar only if you pick it in a custom gauge.

**General.** *Popover opacity* runs from 30 % to fully opaque; the popover
is translucent by default, and this keeps it readable over light windows.
*Launch at login* registers the app with macOS. *Check for updates* is off by
default; when on, Rations asks GitHub for the latest release every 6 hours
and shows a link in the footer when it is newer than the running version.
Nothing is downloaded or installed automatically.

**Usage Hub.** Off by default. When on, Rations serves the signed-in Claude
and Codex accounts' usage to [T3 Code](https://github.com/pingdotgg/t3code),
which reads it as a [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI)
hub. In T3 Code, add a CLIProxyAPI hub with the URL and key shown here. The
port defaults to 8318; the key is random, kept in the keychain (account `hub`),
and can be replaced. See [Usage hub](#usage-hub) for what it answers.

Settings are stored in the app's user defaults (`no.enso.rations`), the
account list included — tags and names only, never tokens.

## Refresh behaviour

Each account has its own schedule.

| Situation | Next check |
|---|---|
| Default | 5 min |
| Numbers changed since last check | 2 min |
| Unchanged | doubles: 5 → 10 → 20 min (cap) |
| A window is about to reset | shortly after the reset |
| Rate limited (HTTP 429) | 20 min |
| Manual refresh (↻) | now, then back to 5 min |

The popover footer under each account shows when it was last updated and when
the next check is due.

## How it works

All four providers expose the usage numbers behind an OAuth token:

- Claude: `GET https://api.anthropic.com/api/oauth/usage`, the endpoint Claude
  Code uses for `/usage`. Sign-in is the same PKCE flow as Claude Code.
- Codex: `GET https://chatgpt.com/backend-api/wham/usage`, the endpoint the
  Codex CLI uses. Sign-in is the same PKCE flow as `codex login`.
- Copilot: `GET https://api.github.com/copilot_internal/user`, the endpoint the
  Copilot editor extensions use. Sign-in is GitHub's device flow with the
  Copilot app's client id. Unlimited quotas (chat, completions on most plans)
  are hidden; the metered premium-request quota is shown with counts.
- Antigravity: `POST https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary`
  (production `cloudcode-pa` if that 404s), the quota summary behind `agy
  /usage`, for the Cloud Code project `loadCodeAssist` returns. Sign-in is a
  Google PKCE flow with the Antigravity app's OAuth client. Unlike the other
  providers' clients, Google's also needs a client secret at the token
  endpoint. It is not confidential (Google and RFC 8252 say as much for
  installed apps), but it is Google's, so Rations does not ship it: it reads it
  from your own install (`~/.local/bin/agy`, Homebrew's `agy`, or the language
  server in `Antigravity.app`), checks it with Google, and keeps it in memory. Each model group
  (Gemini; Claude and GPT) has its own 5-hour and weekly limit; the menu bar
  shows the most-used of each, the popover all of them, including model-only
  limits such as Gemini 4 Argon's.

These endpoints are not publicly documented, so field names may change. The
Claude parser accepts any limit key that carries a `utilization` value; unknown
keys are shown only when they have a reset time. It also reads the named Fable
allowance from the API's `limits` array.

The app talks only to anthropic.com, claude.ai, openai.com, chatgpt.com and
github.com. With "Check for updates" on (off by default) it also asks
api.github.com for this repository's latest release every 6 hours and shows a
link in the popover when it is newer than the running version. With the usage
hub on (off by default) it also accepts connections on 127.0.0.1.

## Usage hub

The hub listens on 127.0.0.1 only and implements the two CLIProxyAPI
management endpoints T3 Code reads quota through, both behind the key
(`Authorization: Bearer <key>` or `X-Management-Key`):

- `GET /v0/management/auth-files` lists the signed-in Claude and Codex
  accounts: id, provider, email, and for Codex the ChatGPT workspace id.
- `POST /v0/management/api-call` is, on a real hub, a request sent upstream
  with the account's token. Here it only answers a GET of that account's usage
  URL, with the response body from Rations' last check. Anything else gets
  `status_code` 403, so T3 Code shows no Codex reset credits.

It makes no upstream requests of its own and never returns tokens. Usage is as
fresh as the [refresh schedule](#refresh-behaviour) makes it.

## Release

`make release` builds `build/rations-<version>.dmg`: the app and an
Applications shortcut over `Resources/dmg-background.tiff`, laid out by Finder
via `scripts/dmg-layout.applescript`. The icon and background are drawn by
`scripts/artwork.swift`; `make artwork` regenerates them. To make it installable
on other Macs it must be signed with a Developer ID and notarized. The script
uses the Developer ID Application identity in your keychain if there is one;
set `SIGN_IDENTITY` to choose explicitly. Notarization runs when
`NOTARY_PROFILE` is set:

```sh
NOTARY_PROFILE=rations make release
```

One-time setup with an Apple Developer account:

1. Create a *Developer ID Application* certificate at
   developer.apple.com/account/resources/certificates. Generate the signing
   request in Keychain Access (Certificate Assistant → Request a Certificate
   From a Certificate Authority), upload it, download the certificate and
   double-click it. `security find-identity -v -p codesigning` then lists it.
2. Create an app-specific password at account.apple.com and store it:
   ```sh
   xcrun notarytool store-credentials rations \
       --apple-id you@example.com --team-id TEAMID
   ```

Without `SIGN_IDENTITY` the DMG is ad-hoc signed and only runs on the building
Mac. Signing with a Developer ID also stops the keychain prompt after rebuilds.

### GitHub Actions

`.github/workflows/release.yml` does the same on a macOS runner, on every
`v*` tag (attaching the DMG to a GitHub Release) or by hand from the Actions
tab (DMG as a build artifact). A tag `v1.2` produces `rations-1.2.dmg`
with that version stamped into the app; manual runs and local builds are
stamped from `git describe --tags` instead. After a tagged release it also bumps the cask in
[headconnect/homebrew-tap](https://github.com/headconnect/homebrew-tap) via
`scripts/bump-cask.sh`, when `TAP_GITHUB_TOKEN` is set. It needs these
repository secrets:

| Secret | Value |
|---|---|
| `MACOS_CERTIFICATE_P12` | Developer ID identity exported as PKCS#12, base64-encoded |
| `MACOS_CERTIFICATE_PASSWORD` | password of that PKCS#12 file |
| `NOTARY_APPLE_ID` | Apple ID email of the developer account |
| `NOTARY_PASSWORD` | app-specific password for that Apple ID |
| `TAP_GITHUB_TOKEN` | fine-grained PAT with *Contents: read and write* on `headconnect/homebrew-tap` (optional) |

Export the identity from Keychain Access (right-click the certificate →
Export) or with `security export -t identities -f pkcs12`, then
`base64 -i cert.p12 | gh secret set MACOS_CERTIFICATE_P12`.

## Development

```sh
make build   # debug build
make test    # checks: refresh policy, response parsing, PKCE, accounts, usage hub (no Xcode needed)
make app     # release build + app bundle in build/
make release # DMG, signed and notarized when SIGN_IDENTITY/NOTARY_PROFILE are set
make artwork # regenerate Resources/rations.icns and the DMG background
swift run RationsChecks --live   # also fetch and print usage for signed-in accounts
```

Layout:

```
Sources/RationsCore/
  Model/       Provider, Account, MenuBarOptions, UsageWindow/UsageSnapshot, OAuthTokens, errors
  Auth/        PKCE, JWT claims, keychain vault + migration, localhost callback server, private sign-in window
  Providers/   ClaudeService, CodexService, CopilotService, AntigravityService, shared HTTP helpers
  Scheduler/   RefreshPolicy (pure), AccountStore (accounts + vault), AccountMonitor (state + polling loop)
  Hub/         usage hub for T3 Code: HubAPI (pure routing), HubServer (loopback HTTP), UsageHub (settings + state)
  UI/          status item + popover (App), menu bar label, per-account section, settings, formatting
Sources/rations/        main.swift, launches the app
Sources/RationsChecks/  check runner used by `make test`
```

Development builds are ad-hoc signed, so each build has a new signature and
macOS may ask for keychain access once after rebuilding; choose *Always Allow*.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) before opening a PR.

## License

[MIT](LICENSE)

## AI disclosure

See [AI_DISCLOSURE.md](AI_DISCLOSURE.md).
