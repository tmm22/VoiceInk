# AI Enhancement Guide (VoiceLink Community 65.2)

AI Enhancement lets you post-process transcripts using prompts and optional cloud providers. It works alongside Quick Rules and Word Replacements to produce polished text.

## Enable Enhancement

1. Open the sidebar and choose `Enhancement`.
2. Turn on **Enable Enhancement**.
3. If you see "AI enhancements are disabled," enable AI enhancement features in Settings.

When enhancement is enabled, the recorder can apply the selected prompt after transcription.

## Choose a Provider

In **AI Provider Integration** you can select and configure providers.

- **OpenAI, Anthropic, Gemini, Mistral, Groq, Cerebras, OpenRouter, ZAI**: add API keys and select a model.
- **Ollama**: connect to a local server (default `http://localhost:11434`) and pick a local model.
- **Custom**: use an OpenAI-compatible HTTPS endpoint.

Tip: If models are missing for OpenRouter, click the refresh icon to load the latest list.

## Request Settings

- **Request Timeout**: increase if responses are slow or prompts are complex.
- **Reasoning Effort**: choose low/medium/high based on quality vs speed (supported by select models).

## Global Personal Context

Use **Global Personal Context** to inject a persistent bio or style guide into every request.

Example:
- "I am a product manager. Keep responses concise and action-oriented."

## Prompts and Persona

The **Enhancement Prompts & Persona** section lets you:

- Add new prompts.
- Edit existing prompts.
- Drag to reorder prompts (affects shortcut order).
- Delete prompts you no longer need.

The selected prompt becomes the default for new recordings.

## Context Awareness

Enable **Context Awareness** to include active window context for richer rewrites.

## Enhancement Shortcuts

With the recorder visible:

- **Toggle AI Enhancement**: `Command + E`.
- **Switch Prompt**: `Command + 1` through `Command + 0`.

## Troubleshooting

- **No providers connected**: add API keys in the Enhancement view.
- **Custom endpoint errors**: ensure the URL is HTTPS and OpenAI-compatible.
- **Ollama disconnected**: confirm the server is running and the base URL is correct.
