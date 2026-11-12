# LanguageScout

LanguageScout helps you find players who speak your language in WoW Forever and Anniversary. It adds language flags to chat and player tooltips, learns from chat and other clues, and shares known languages with other addon users.

## Features

- Detect languages from chat words and phrases, distinctive characters, and recognized Questie announcements.
- Choose which chats to scan: public channels, guild, party, raid, instance group, say, and yell.
- Enable optional detection from guild names and localized hunter pet names.
- Mark players manually through their context menu or the settings page, and assign languages to guilds.
- Share known languages with guild and group members who use the addon. Nearby friendly users can also announce their own language.
- Search and filter saved players by language or source, including **Confirmed by player** and **Synced guess**.
- Undo an automatic guess and manage rejected guesses with **Allow again**.
- Choose your own language and see your effective language in settings.
- Add your language tag (for example, `[FR]`) to outgoing messages, with a master opt-out and separate channel switches.
- Show language flags to the left or right of player names on accessible nameplates.

Automatic detection uses clues and can make mistakes. Manual player assignments are protected from automatic detection and received language announcements. A player's own announcement can correct an inferred language.

## How detection works

Each message is evaluated independently. A leading supported language tag, such as `[FR]`, takes priority over words in the message. Tags are case-insensitive and must be followed by whitespace or the end of the message; tags mentioned later in a sentence are ignored. A tag can correct an inferred language, while manual assignments, confirmed player announcements, and undone guesses remain protected. Tag detection follows the existing automatic-detection, channel, and per-language switches, independently of your outgoing-prefix settings.

Without a supported leading tag, distinctive characters and recognized localized announcements can identify a language directly. Otherwise, matching keywords contribute points: most words or phrases score 2, while weaker clues score 1. A language needs at least 2 points; the highest total wins, with the strongest individual clue breaking a score tie. An unresolved tie stays unknown.

Multi-word phrases match complete words in order, allowing extra whitespace and punctuation, including typographic apostrophes and dashes. For example, `merci beaucoup`, `MERCI, BEAUCOUP!`, and `merci—beaucoup` match the same French phrase. Phrase words must occur in one message. Repeating a weak word does not increase its score.

English, German, French, Spanish, Russian, Ukrainian, Italian, and Portuguese include additional conversational phrases for finding groups, invitations, missing roles, travel, thanks, and greetings. English uses multi-word phrases; isolated greetings and shared shorthand such as `hi`, `LFG`, `tank`, and `gg` do not identify English by themselves. You can add custom phrases in the automatic-detection settings.

## Supported languages

English, German, Spanish, Russian, Ukrainian, French, Italian, Swedish, Norwegian, Danish, Turkish, Polish, Portuguese, Dutch, and Czech/Slovak.

English supports manual assignments, incoming and outgoing `[EN]` tags, automatic selection from `enUS`/`enGB`, and language sharing. Its flag icon uses the Union Jack.

Each language has separate controls for its context-menu entry and automatic detection. You can also add custom detection keywords.

## Installation

1. Close WoW.
2. Extract the `LanguageScout` folder into `Interface/AddOns` and enable the addon.
3. Start WoW and type `/languagescout` or `/ls` to open settings.

You can also open **Settings → AddOns → LanguageScout**.

## Your language

Select a language in settings or leave it on **Automatic**. Manual selection always takes priority. On Forever, Automatic uses your supported preferred language, falling back to your supported client/UI language if the preference is unavailable, still loading, or unsupported. Once a supported preference arrives, it takes priority again. On Anniversary, Automatic uses your supported client language. The effective-language display shows the result, including when neither source provides a supported language.

## Outgoing language tags

In **LanguageScout → Outgoing messages**, you can turn off **Prefix my outgoing messages** or choose channels individually: public channels, guild, party, raid, instance group, say, and yell. The feature and all seven channel switches start enabled. These settings are independent of detection, flag display, and synchronization.

Messages sent through the chat edit box receive your effective-language tag, for example `[FR] Bonjour à tous !`, visible to everyone. An existing language tag is preserved. No tag is added when your effective language is unavailable or the tag would exceed the message length limit. Whispers, officer chat, raid warnings, emotes, slash commands, and direct messages generated by other addons are left unchanged.

## Nameplate flags

Open **LanguageScout → Nameplates** and choose **Off**, **Left**, or **Right**. The default is **Off**. Flags use saved player languages and update as assignments change; unknown players, pets, and NPCs have no flag. The setting is independent of chat and tooltip flags.

Player nameplates must be enabled in WoW. Blizzard nameplates and Plater are supported, including Plater's regular labels and name-only mode. Flags follow the active label and its parent visibility/fading. This feature does not modify the plain world-rendered floating names. Restricted nameplates, including some friendly plates, are skipped. Other nameplate replacements may need separate support.

To test in game, enable friendly player nameplates, mark a nearby player manually, and switch **Left → Right → Off**. Check that the flag follows the name, changes when you change the language, disappears when you remove the assignment, and stays absent on pets/NPCs. Walk away and return to check reused nameplates, then reload to confirm the selected position persists.

With Plater enabled, also test its normal health-bar names and name-only mode. Disabling Plater should leave Blizzard nameplate flags working. The local `Plater/` source reference is excluded from Git and release ZIPs; LanguageScout does not bundle Plater or its libraries.

## Commands

- `/languagescout` or `/ls`: open settings.
- `/lsdebug last`: inspect the latest automatic detection.
- `/lsdebug test`: run the built-in detection checks.
- `/lsdebug records`: show saved-record counts.
- `/lsdebug on`, `/lsdebug off`, `/lsdebug tooltip`, or `/lsdebug sync`: diagnostic logging.

`/languagescoutdebug` is an alias for `/lsdebug`.

## Development

From the project directory:

```sh
python -m pip install -r tests/requirements.txt
python tests/run_tests.py
```

The suite runs Lua 5.1 with mocked WoW APIs. Native UI and multiplayer behavior also need in-game verification.

Build an installable ZIP locally with `python scripts/build_release.py`. The package is written to `dist/LanguageScout-<version>.zip`, with one `LanguageScout/` folder containing the runtime files and textures.

On every push to `main`, GitHub Actions runs the tests and builds the ZIP. If the version in `LanguageScout.toc` has no release yet, it creates tag `v<version>` and publishes a GitHub release with the ZIP and generated release notes. Existing releases are left unchanged: bump `## Version` in the TOC to publish another release. The workflow can also be run manually on `main`.
