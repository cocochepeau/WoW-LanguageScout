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

Automatic detection uses clues and can make mistakes. Manual player assignments are protected from automatic detection and received language announcements. A player's own announcement can correct an inferred language.

## How detection works

Each message is evaluated independently. Distinctive characters and recognized localized announcements can identify a language directly. Otherwise, matching keywords contribute points: most words or phrases score 2, while weaker clues score 1. A language needs at least 2 points; the highest total wins, with the strongest individual clue breaking a score tie. An unresolved tie stays unknown.

Multi-word phrases match complete words in order, allowing extra whitespace and punctuation, including typographic apostrophes and dashes. For example, `merci beaucoup`, `MERCI, BEAUCOUP!`, and `merci—beaucoup` match the same French phrase. Phrase words must occur in one message. Repeating a weak word does not increase its score.

German, French, Spanish, Russian, Ukrainian, Italian, and Portuguese include additional conversational phrases for finding groups, invitations, missing roles, travel, thanks, and greetings. You can add custom phrases in the automatic-detection settings.

## Supported languages

German, Spanish, Russian, Ukrainian, French, Italian, Swedish, Norwegian, Danish, Turkish, Polish, Portuguese, Dutch, and Czech/Slovak.

Each language has separate controls for its context-menu entry and automatic detection. You can also add custom detection keywords.

## Installation

1. Close WoW.
2. Extract the `LanguageScout` folder into `Interface/AddOns` and enable the addon.
3. Start WoW and type `/languagescout` or `/ls` to open settings.

You can also open **Settings → AddOns → LanguageScout**.

## Your language

Select a language in settings or leave it on **Automatic**. On Forever, Automatic uses your supported preferred language; on Anniversary, it uses your supported client language. The effective-language display shows the result, including when no supported language is available.

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
