# Power Mode Guide (VoiceLink Community 65.2)

Power Mode lets VoiceLink Community automatically apply transcription and AI enhancement settings based on the app or website you are using. It is designed for context-aware workflows: one setup for email, another for meetings, another for coding, and so on.

## What Power Mode Controls

- Transcription model and language.
- AI enhancement provider, model, and prompt.
- Context awareness (screen capture context).
- Auto Send (press Return/Enter after paste).
- A default fallback mode when nothing matches.

## Enable Power Mode

1. Open `Settings`.
2. Go to `Transcription`.
3. In `Power Mode`, turn on **Enable Power Mode**.
4. Optional: enable **Auto-Restore Preferences** to revert to your previous settings after each recording.

If Power Mode is enabled but no configurations are active, the app keeps your current settings.

## Create Your First Power Mode

1. Open the sidebar and choose `Power Mode`.
2. Click **Add Power Mode**.
3. Choose an emoji and give the mode a clear name (example: "Work", "Podcast").
4. Optional: toggle **Set as default power mode**. This applies when no trigger matches.
5. Configure triggers and settings (details below).
6. Click **Add New Power Mode** or **Save Changes**.

## Set Triggers

### Applications

- Click **Add App** and pick a running or installed application.
- Each app becomes a trigger. When that app is active, this Power Mode applies.

### Websites

- Enter a domain like `google.com` or `docs.google.com`.
- Avoid trailing paths when possible; domain-level matching is more reliable.

## Configure Transcription

1. In the **Transcription** section, select a model.
2. If the model supports multiple languages, choose a language or keep **Autodetected**.
3. If you only use English-only models, the language picker is hidden.

Tip: If no models are listed, open `AI Models` and download or connect one first.

## Configure AI Enhancement

1. Turn on **Enable AI Enhancement**.
2. Choose an **AI Provider** and **AI Model**.
3. Pick an **Enhancement Prompt** from your prompt grid.
4. Optional: enable **Context Awareness** to include screen context.

Note: AI enhancement options appear only if AI enhancement features are enabled in Settings.

## Advanced Settings

- **Auto Send**: automatically presses Return/Enter after pasting. Use this for chat apps and quick forms.

## Manage Power Modes

- **Enable/disable**: switch a mode on or off in the Power Mode list.
- **Reorder**: click **Reorder** to drag modes into priority order.
- **Delete**: edit a mode and click **Delete**.

## Quick Switching

- Use `Option + 1` through `Option + 0` to switch between Power Modes.
- The shortcut order matches the Power Mode list order.

## Troubleshooting

- **"Power Mode Still Active"**: Disable all active Power Modes before toggling Power Mode off in Settings.
- **No transcription models available**: Download a local model or connect a cloud provider in `AI Models`.
- **No AI models available**: Configure providers in `Enhancement` and verify API keys.
