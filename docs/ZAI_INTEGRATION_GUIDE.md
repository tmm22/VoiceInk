# Z.AI Integration Guide

This document describes the implementation of Z.AI (Zhipu AI) as a cloud provider in VoiceInk, enabling both cloud transcription via GLM-ASR-Nano-2512 and AI enhancement via GLM language models.

## Overview

Z.AI is integrated as a comprehensive cloud provider offering:

1. **Cloud Transcription** - GLM-ASR-Nano-2512 speech recognition model
2. **AI Enhancement** - GLM-4.6 and other LLM models for text refinement

Both APIs are OpenAI-compatible, simplifying integration with existing VoiceInk patterns.

---

## Features

### GLM-ASR-Nano-2512 (Speech Recognition)

| Property | Value |
|----------|-------|
| **Model ID** | `glm-asr-2512` |
| **Parameters** | 1.5B |
| **Accuracy** | 0.0717 CER (Character Error Rate) |
| **Languages** | 17+ languages including Chinese, English, Cantonese, French, German, Japanese, Korean, Spanish, Arabic |
| **Max Duration** | 30 seconds per request |
| **Max File Size** | 25 MB |
| **Pricing** | ~$0.0024/minute |

**Key Capabilities:**
- Exceptional dialect support (Cantonese, Sichuanese, etc.)
- Low-volume speech robustness
- State-of-the-art performance on Chinese benchmarks

### GLM Language Models (AI Enhancement)

| Model | Context | Description | Pricing |
|-------|---------|-------------|---------|
| `glm-4.5-flash` | 128K | **Free tier** - Fast, cost-effective | Free |
| `glm-4.6` | 200K | Latest flagship, best performance | $0.6/$2.2 per MTok |
| `glm-4.5` | 128K | Previous flagship | $0.6/$2.2 per MTok |
| `glm-4.5-air` | 128K | Lightweight, faster | $0.2/$1.1 per MTok |
| `glm-4-32b-0414-128k` | 128K | Open weights model | $0.1/$0.1 per MTok |

---

## API Reference

### Audio Transcription API

**Endpoint:** `https://api.z.ai/api/paas/v4/audio/transcriptions`

**Method:** POST

**Headers:**
```
Authorization: Bearer <API_KEY>
Content-Type: multipart/form-data
```

**Request Body (multipart/form-data):**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `file` | File | Yes | Audio file (.wav, .mp3) |
| `model` | String | Yes | Model ID (`glm-asr-2512`) |
| `stream` | Boolean | No | `false` for synchronous (default) |
| `hotwords` | Array | No | Custom vocabulary for better recognition |
| `prompt` | String | No | Previous transcription for context |

**Response:**
```json
{
  "id": "task_123",
  "created": 1702345678,
  "request_id": "req_abc",
  "model": "glm-asr-2512",
  "text": "Transcribed text content here"
}
```

### Chat Completions API (AI Enhancement)

**Endpoint:** `https://api.z.ai/api/paas/v4/chat/completions`

**Method:** POST

**Headers:**
```
Authorization: Bearer <API_KEY>
Content-Type: application/json
```

**Request Body:**
```json
{
  "model": "glm-4.5-flash",
  "messages": [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "Please improve this text: ..."}
  ],
  "temperature": 0.7,
  "max_tokens": 4096
}
```

**Response:**
```json
{
  "id": "chatcmpl_123",
  "created": 1702345678,
  "model": "glm-4.5-flash",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Improved text content here"
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 50,
    "completion_tokens": 100,
    "total_tokens": 150
  }
}
```

---

## Implementation Details

### Files Modified/Created

| File | Action | Purpose |
|------|--------|---------|
| `VoiceInk/Models/TranscriptionModel.swift` | Modified | Added `case zai = "Z.AI"` to `ModelProvider` enum |
| `VoiceInk/Models/PredefinedModels.swift` | Modified | Added `CloudModel` for GLM-ASR-Nano-2512 |
| `VoiceInk/Services/CloudTranscription/ZAITranscriptionService.swift` | **Created** | New service for Z.AI audio transcription |
| `VoiceInk/Services/CloudTranscription/CloudTranscriptionService.swift` | Modified | Added routing to ZAI service |
| `VoiceInk/Views/AI Models/CloudModelCardRowView.swift` | Modified | Added provider key and verification support |
| `VoiceInk/Services/AIEnhancement/AIService.swift` | Modified | Added Z.AI to AIProvider enum with models |
| `VoiceInk/Views/AI Models/APIKeyManagementView.swift` | Modified | Added API key URL and free tier label |

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         User Interface                          │
│  CloudModelCardRowView, APIKeyManagementView                    │
└─────────────────────────┬───────────────────────────────────────┘
                          │
          ┌───────────────┴───────────────┐
          │                               │
          ▼                               ▼
┌─────────────────────┐       ┌─────────────────────┐
│  Cloud Transcription │       │   AI Enhancement    │
│  CloudTranscription  │       │     AIService       │
│      Service         │       │                     │
└─────────┬───────────┘       └─────────┬───────────┘
          │                               │
          ▼                               ▼
┌─────────────────────┐       ┌─────────────────────┐
│ ZAITranscription    │       │ Z.AI Chat API       │
│     Service         │       │ (OpenAI-compat)     │
└─────────┬───────────┘       └─────────┬───────────┘
          │                               │
          └───────────────┬───────────────┘
                          │
                          ▼
                ┌─────────────────┐
                │   api.z.ai      │
                │  (HTTPS API)    │
                └─────────────────┘
```

### Keychain Storage

API keys are stored securely in macOS Keychain:
- **Key Name:** `ZAI`
- **Access:** Via `KeychainManager.getAPIKey(for: "ZAI")`

---

## User Guide

### Getting an API Key

1. Visit [Z.AI Console](https://z.ai/manage-apikey/apikey-list)
2. Sign up or log in to your account
3. Create a new API key
4. Copy the key (it won't be shown again)

### Configuring in VoiceInk

#### For Cloud Transcription:
1. Open VoiceInk Settings
2. Navigate to **AI Models** > **Cloud Models**
3. Find "GLM-ASR-Nano (Z.AI)"
4. Click **Configure**
5. Enter your Z.AI API key
6. Click **Verify** to validate
7. Set as default if desired

#### For AI Enhancement:
1. Open VoiceInk Settings
2. Navigate to **AI Enhancement** > **API Keys**
3. Select "ZAI" from the provider dropdown
4. Enter your Z.AI API key
5. Click **Verify and Save**
6. Select your preferred GLM model

### Usage Tips

1. **Free Tier:** Use `glm-4.5-flash` for cost-free AI enhancement
2. **Best Accuracy:** Use `glm-4.6` for highest quality transcription enhancement
3. **Chinese Content:** GLM-ASR excels at Chinese, Cantonese, and mixed Chinese-English
4. **30-Second Limit:** Audio clips longer than 30 seconds will fail - keep recordings short

---

## Limitations

1. **Audio Duration:** Maximum 30 seconds per transcription request
2. **File Size:** Maximum 25 MB per audio file
3. **Supported Formats:** `.wav`, `.mp3` (recommended: WAV at 16kHz)
4. **Rate Limits:** Subject to Z.AI's rate limiting policies

---

## Troubleshooting

### Common Issues

**"Missing API Key" Error:**
- Ensure you've entered and verified your API key in settings
- Check that the key is correctly copied without extra spaces

**"API Request Failed (401)" Error:**
- Invalid API key - regenerate from Z.AI console
- API key may have been revoked or expired

**"API Request Failed (413)" Error:**
- Audio file too large - ensure it's under 25 MB
- Audio too long - keep under 30 seconds

**"No Transcription Returned" Error:**
- Audio may be silent or corrupted
- Try a different audio file
- Check audio format (use WAV or MP3)

### Debug Logging

Enable debug logging to troubleshoot issues:
```swift
#if DEBUG
print("Z.AI API response: \(responseData)")
#endif
```

Logs are available in Console.app under the `ZAIService` category.

---

## Security Considerations

1. **HTTPS Only:** All API calls use HTTPS encryption
2. **Keychain Storage:** API keys stored in macOS Keychain (not UserDefaults)
3. **Ephemeral Sessions:** Network requests use ephemeral URLSession (no disk cache)
4. **No Logging of Secrets:** API keys are never logged in production builds

---

## References

- [Z.AI Developer Documentation](https://docs.z.ai/)
- [GLM-ASR-Nano-2512 on HuggingFace](https://huggingface.co/zai-org/GLM-ASR-Nano-2512)
- [GLM-ASR GitHub Repository](https://github.com/zai-org/GLM-ASR)
- [Z.AI Pricing](https://docs.z.ai/guides/overview/pricing)
- [Z.AI API Reference](https://docs.z.ai/api-reference/introduction)

---

## Changelog

### December 2024
- Initial implementation of Z.AI integration
- Added GLM-ASR-Nano-2512 for cloud transcription
- Added GLM-4.6, GLM-4.5, GLM-4.5-flash, GLM-4.5-air, GLM-4-32B for AI enhancement
- Integrated with existing VoiceInk cloud provider architecture
