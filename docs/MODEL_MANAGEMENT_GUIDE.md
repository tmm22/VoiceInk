# AI Model Management Guide (VoiceLink Community 65.2)

Use the AI Models workspace to manage transcription engines, download local models, and configure cloud options.

## Open the AI Models Workspace

1. Open the sidebar and select `AI Models`.
2. If the section is hidden, enable AI enhancement features in Settings.

## Default Model

The top card shows the current default transcription model. Use the **Set Default** action on any model card to change it.

## Language Selection

Use the language picker to select a transcription language or keep **Auto** for multilingual models.

## Model Filters

Use the filter bar to switch between:

- **Recommended**: curated local and cloud options.
- **Local**: bundled Whisper/Parakeet/SenseVoice/FastConformer models.
- **Cloud**: cloud transcription providers.
- **Custom**: user-defined cloud endpoints.

## Download and Manage Local Models

1. Open the **Local** filter.
2. Click **Download** on a model card.
3. Use **Set Default** to make it the default model.
4. Use **Delete** to remove downloaded files.

### Import a Local Model

In the Local section, click **Import Local Model…** and select a `.bin` or `.gguf` file for a fine-tuned Whisper model.

## Cloud Models

Cloud models appear under the **Cloud** filter. Configure API keys and model selections as needed:

- Use the gear icon to open Model Settings.
- Connect providers in the `Enhancement` section when required.

## Custom Models

1. Switch to the **Custom** filter.
2. Click **Add Custom Model**.
3. Provide a name, endpoint, and API key (OpenAI-compatible).

Custom models can be edited or removed at any time.

## Model Settings (Gear Icon)

The model settings panel lets you:

- Edit the transcription **Output Format** prompt.
- Toggle **Add space after paste**.
- Enable/disable **Automatic text formatting**.
- Enable/disable **Voice Activity Detection (VAD)** for local models.

## Troubleshooting

- **No models available**: download a local model or configure a cloud provider.
- **Model download stuck**: wait for the current download to complete before starting another.
- **Custom model errors**: verify the endpoint is HTTPS and OpenAI-compatible.
