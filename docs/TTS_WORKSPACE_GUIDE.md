# Text-to-Speech Workspace Guide (VoiceLink Community 65.2)

The Text-to-Speech (TTS) Workspace turns text into natural audio using local voices or cloud providers. It includes batch generation, translation, transcript export, and a full playback timeline.

## Access the Workspace

1. Open the sidebar and choose `Text to Speech`.
2. If the workspace is locked, enable AI enhancement features in Settings.

## Workspace Layout

- **Command strip (top)**: provider, voice, generate, preview, translate, batch, export, and inspector controls.
- **Composer (center)**: the main text editor and utility tools.
- **Context panels (right or bottom)**: Queue, History, Library, and Glossary.
- **Playback bar (bottom)**: play, pause, seek, and speed controls.

## Generate Speech

1. Select a **Provider** (OpenAI, ElevenLabs, Google, or Tight Ass Mode for local voices).
2. Choose a **Voice** (or leave as Default).
3. Enter or paste text in the editor.
4. Click **Generate** (or press `Command + Return`).

The status indicator shows generation progress while audio is being created.

## Voice Preview

- Click **Preview Voice** to listen to samples before generating.
- Use the popover list to audition multiple voices quickly.

## Batch Generation

Batch generation splits your text into segments and generates each segment sequentially.

1. Separate segments with `---` in the editor.
2. Click **Batch**.
3. Track progress in the **Queue** panel.

Tip: Use the **Chunk Helper** utility to preview how segments will split before you start a batch.

## Translation

1. Click **Translate** in the command strip.
2. Choose a target language.
3. Review the translation and select **Use Translation** to replace the editor text.

You can keep the original text or replace it entirely based on the translation setting.

## Add Content Utilities

Open **Add Content** to access utilities:

- **Transcription**: record and transcribe audio into the editor.
- **URL Import**: pull readable text from a web article.
- **Sample Text**: insert curated starter copy.
- **Chunk Helper**: preview how text will split for batch generation.

## Context Panels

- **Queue**: view batch items and progress.
- **History**: revisit previous generations and re-export audio.
- **Library**: save and reuse text snippets.
- **Glossary**: manage pronunciation rules for names and terms.

## Export Audio and Transcripts

From the command strip or the inspector:

- **Export Audio**: save the latest audio file.
- **Export Transcript**: save `SRT` or `VTT` captions for the current audio.

The **History** panel also allows per-item exports.

## Inspector (Settings Sidebar)

Open the inspector to fine-tune:

- **Voice Configuration**: provider, voice, and style controls.
- **Audio & Playback**: volume, speed, loop, and format.
- **Export**: audio format and transcript settings.
- **Cost & Usage**: estimated usage for cloud providers.
- **System**: batch and workspace preferences.

## Troubleshooting

- **No voices listed**: verify API keys or select Tight Ass Mode for local voices.
- **Export disabled**: generate audio first, then export.
- **Batch button disabled**: add `---` separators to create multiple segments.
