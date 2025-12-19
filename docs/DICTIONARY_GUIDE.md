# Dictionary and Custom Vocabulary Guide (VoiceLink Community 65.2)

The Dictionary settings let you shape how transcriptions are cleaned and corrected. This includes Quick Rules, Word Replacements, and Correct Spellings.

## Open Dictionary Settings

1. Open `Settings`.
2. Go to `Transcription`.
3. Click **Open Dictionary Settings**.

Use the cards at the top to switch between sections.

## Quick Rules

Quick Rules apply predictable offline cleanup rules (filler words, duplicates, spacing, and common phrasing fixes).

- Toggle categories and individual rules.
- Use the built-in test area to preview output.

For the full walkthrough, see `QUICK_RULES_USER_GUIDE.md`.

## Word Replacements

Word Replacements automatically swap words or phrases after transcription.

### Add a Replacement

1. Open **Word Replacements**.
2. Click the **+** button.
3. Enter the original word or phrase.
4. Enter the replacement text.

Tips:
- You can enter comma-separated originals (example: `Voice Ink, VoiceInk`) to map multiple variations to one replacement.
- Use this for brand names, acronyms, or formatting fixes.

### Edit or Delete

- Click a row to edit.
- Use the delete action in each row to remove a replacement.

## Correct Spellings (Custom Vocabulary)

Correct Spellings improves recognition of names and custom terms.

1. Open **Correct Spellings**.
2. Add one or more words (comma-separated is supported).
3. Words are sorted alphabetically; use the sort toggle to flip order.

Note: This section requires AI enhancement to be enabled, since it is applied during enhancement.

## Import and Export

The Dictionary header includes import/export buttons:

- **Import**: bring in dictionary items and replacements from a file.
- **Export**: back up your current dictionary and replacements.

These exports are separate from the full app settings export.

## Best Practices

- Keep replacements short and deterministic.
- Put proper nouns and jargon in Correct Spellings.
- Use Quick Rules for general cleanup instead of heavy AI rewrites.
