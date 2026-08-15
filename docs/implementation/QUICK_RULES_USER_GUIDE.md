# Quick Rules User Guide

**Feature:** Dictionary Quick Rules for Automatic Text Cleanup  
**Version:** 1.0  
**Status:** Available in VoiceInk Community Fork

---

## What Are Quick Rules?

Quick Rules provide **instant, predictable text cleanup** without requiring AI enhancement. They're perfect for:

- **Casual to formal conversion** (gonna → going to)
- **Removing filler words** (um, uh, like)
- **Fixing spacing and punctuation**
- **Removing duplicate words** (the the → the)
- **Basic text standardization**

Unlike AI enhancement, Quick Rules:
- ✅ **Work offline** - No internet required
- ✅ **Instant processing** - No API calls or delays
- ✅ **100% predictable** - Same input always produces same output
- ✅ **Privacy-focused** - Nothing leaves your device
- ✅ **Battery-friendly** - Minimal resource usage

---

## Quick Rules vs. AI Enhancement

VoiceInk offers **three layers** of text processing, each serving a different purpose:

### Processing Pipeline

```
Raw Transcription
       ↓
[1] Quick Rules (Optional)
       ↓
[2] Word Replacements (Optional)
       ↓
[3] AI Enhancement (Optional)
       ↓
Final Output
```

### When to Use Each Feature

| Feature | Best For | Example |
|---------|----------|---------|
| **Quick Rules** | Basic cleanup, casual → formal | "gonna" → "going to" |
| **Word Replacements** | Custom terminology, brand names | "VoiceInk" → "VoiceLink Community" |
| **AI Enhancement** | Context-aware rewriting, summarization | "make this professional and concise" |

### Recommended Workflows

#### Workflow 1: Quick Dictation (Fastest)
```
Raw Transcription → Quick Rules → Done
```
**Use when:** Taking quick notes, casual writing, speed is priority  
**Processing time:** <1ms

#### Workflow 2: Professional Writing (Balanced)
```
Raw Transcription → Quick Rules → Word Replacements → Done
```
**Use when:** Professional emails, documentation, consistent terminology needed  
**Processing time:** <5ms

#### Workflow 3: High-Quality Output (AI-Enhanced)
```
Raw Transcription → Quick Rules → Word Replacements → AI Enhancement → Done
```
**Use when:** Important documents, creative writing, need context-aware improvements  
**Processing time:** 2-5 seconds (depending on AI provider)

---

## Getting Started

### 1. Access Quick Rules

1. Open **Settings** (⌘,)
2. Navigate to **Dictionary** in the sidebar
3. Select **Quick Rules** (first tab)

### 2. Enable Quick Rules

1. Toggle **Enable** switch in the top right
2. Quick Rules will now apply automatically to all transcriptions

### 3. Test the Feature

**Live Preview:**
1. In the **Test Rules** section, type: `I'm gonna wanna kinda go there`
2. See instant transformation: `I'm going to want to kind of go there`

**Or use quick test buttons:**
- "I'm gonna wanna kinda go there" (casual language test)
- "um, you know, like, it's the the best" (filler words + duplicates test)

---

## Available Rule Categories

### 1. Casual to Formal (8 rules, enabled by default)

Converts casual contractions to formal equivalents:

| Input | Output |
|-------|--------|
| gonna | going to |
| wanna | want to |
| kinda | kind of |
| sorta | sort of |
| gotta | got to |
| shoulda | should have |
| woulda | would have |
| coulda | could have |

**Example:**
```
Input:  "I'm gonna wanna check if we shoulda done that"
Output: "I'm going to want to check if we should have done that"
```

### 2. Filler Words (4 rules, disabled by default)

Removes common filler words and phrases:

| Pattern | Action |
|---------|--------|
| um | Remove |
| uh | Remove |
| like (filler usage) | Remove |
| you know | Remove |

**Example with rules enabled:**
```
Input:  "um, I think, you know, it's like really good"
Output: "I think it's really good"
```

**Note:** These are disabled by default because context matters. Enable them if you frequently use filler words that should be removed.

### 3. Duplicates (1 rule, enabled by default)

Removes consecutive duplicate words:

```
Input:  "the the project is is ready"
Output: "the project is ready"
```

### 4. Spacing (3 rules, enabled by default)

Fixes spacing issues:

| Rule | Example |
|------|---------|
| Multiple spaces → single space | "hello    world" → "hello world" |
| Trim whitespace | "  text  " → "text" |
| Space before punctuation | "hello ." → "hello." |

### 5. Punctuation (1 rule, disabled by default)

Ensures space after punctuation marks:

```
Input:  "Hello.How are you?I'm fine."
Output: "Hello. How are you? I'm fine."
```

---

## Managing Rules

### Toggle Individual Rules

1. Expand any category (e.g., "Casual to Formal")
2. Use the toggle switch next to each rule
3. Changes apply immediately

### View Rule Details

Each rule shows:
- **Name**: What the rule does
- **Description**: Detailed explanation
- **Pattern**: The text or regex pattern being matched
- **Replacement**: What it's replaced with (or removed if empty)

### Enabled Count

Each category header shows: **"(X/Y enabled)"**
- X = number of enabled rules in this category
- Y = total rules in this category

---

## Creating Custom Rules

### Add a Custom Rule

1. Click **"Add Custom Rule"** button
2. Fill in the form:
   - **Name**: Descriptive name (e.g., "yeah → yes")
   - **Description**: What the rule does
   - **Pattern**: Text or regex to match
   - **Replacement**: What to replace it with
3. Toggle **"Use Regular Expression"** if needed
4. Click **"Add"**

### Custom Rule Examples

#### Simple Text Replacement
```
Name: Convert "yeah" to "yes"
Pattern: yeah
Replacement: yes
Regex: OFF
```

#### Word Boundary Match (Regex)
```
Name: Remove "basically"
Pattern: \bbasically\b
Replacement: (empty)
Regex: ON
```

#### Pattern with Capture Groups (Regex)
```
Name: Fix "can not" to "cannot"
Pattern: \bcan not\b
Replacement: cannot
Regex: ON
```

### Regex Tips

**Word Boundaries:** Use `\b` to match whole words only
```
\bword\b  → matches "word" but not "words" or "keyword"
```

**Capture Groups:** Use `$1`, `$2` to reference matched groups
```
Pattern:     \b(\w+)\s+\1\b
Replacement: $1
Result:      "the the" → "the"
```

**Common Patterns:**
- `\s+` = one or more spaces
- `\w+` = one or more word characters
- `^` = start of text
- `$` = end of text
- `.` = any character

---

## Combining with AI Enhancement

### Scenario 1: Professional Email (Quick Rules + AI)

**Setup:**
1. Enable Quick Rules (casual to formal)
2. Enable AI Enhancement with prompt: "Make this professional"

**Example:**
```
Raw:     "um I'm gonna wanna schedule a meeting you know"
         ↓ Quick Rules
Step 1:  "I'm going to want to schedule a meeting"
         ↓ AI Enhancement
Final:   "I would like to schedule a meeting at your convenience."
```

**Benefits:**
- Quick Rules clean up obvious issues first
- AI Enhancement focuses on higher-level improvements
- Faster AI processing (cleaner input)
- More consistent results

### Scenario 2: Meeting Notes (Quick Rules Only)

**Setup:**
1. Enable Quick Rules (all categories)
2. Disable AI Enhancement

**Example:**
```
Raw:     "the the project is gonna be ready next week basically"
         ↓ Quick Rules
Final:   "the project is going to be ready next week"
```

**Benefits:**
- Instant processing (no AI delay)
- Works offline
- Battery-friendly
- Still professional enough for internal notes

### Scenario 3: Creative Writing (AI Enhancement Only)

**Setup:**
1. Disable Quick Rules (preserve casual voice)
2. Enable AI Enhancement with creative prompt

**Example:**
```
Raw:     "she's gonna tell him the truth kinda suddenly"
         ↓ (Quick Rules OFF)
         ↓ AI Enhancement
Final:   "She reveals the truth to him in an unexpected moment."
```

**Benefits:**
- Preserves author's voice for AI to work with
- AI can make creative decisions about casual language
- Better for fiction/creative content

---

## Best Practices

### ✅ Do:

1. **Test rules with your speaking style**
   - Everyone has different patterns
   - Adjust enabled rules based on your habits

2. **Use live preview frequently**
   - See exactly how rules transform your text
   - Catch unexpected transformations

3. **Start conservative**
   - Begin with default settings
   - Enable more rules as needed

4. **Combine with Word Replacements**
   - Quick Rules for patterns
   - Word Replacements for specific terms

5. **Layer processing strategically**
   - Quick cleanup → Custom terms → AI polish

### ❌ Don't:

1. **Enable all rules blindly**
   - Filler word removal may change meaning
   - Test before enabling everything

2. **Rely only on Quick Rules for critical documents**
   - Use AI Enhancement for important content
   - Quick Rules are basic cleanup only

3. **Create overly complex custom rules**
   - Keep regex patterns simple and tested
   - Complex rules may have unexpected effects

4. **Forget to review output**
   - Always review transcriptions
   - Rules are predictable but may not fit every context

---

## Troubleshooting

### Rules Not Applying

**Check:**
1. Master toggle is enabled (top right)
2. Individual rules are enabled (category toggles)
3. Word Replacement feature is enabled (Dictionary settings)

### Unexpected Results

**Try:**
1. Test in live preview first
2. Disable all rules, enable one at a time
3. Check rule pattern for typos
4. Review examples in documentation

### Performance Issues

**If processing is slow:**
1. Reduce number of enabled rules
2. Simplify custom regex patterns
3. Avoid infinitely-matching patterns

### Custom Rule Not Working

**Verify:**
1. Pattern syntax is correct (test in live preview)
2. Regex toggle matches pattern type
3. Case sensitivity (rules are case-insensitive)
4. Word boundaries if needed (`\b`)

---

## Tips & Tricks

### Tip 1: Create Rule Sets

Create custom rules for different contexts:

**Professional Writing Set:**
- Enable: All "Casual to Formal"
- Enable: All "Spacing"
- Disable: Filler words (let AI handle)

**Quick Notes Set:**
- Enable: Duplicates only
- Disable: Everything else (preserve natural voice)

**Clean Transcription Set:**
- Enable: All categories
- Perfect for final documents

### Tip 2: Test Before Recording

1. Open Quick Rules settings
2. Type your typical speaking patterns in test box
3. Adjust rules based on results
4. Then start recording

### Tip 3: Combine with Power Mode

Different rule sets for different apps/contexts:
- **Email app:** Professional rules
- **Note-taking:** Minimal rules
- **Documentation:** All rules enabled

### Tip 4: Review Patterns

Look at your transcription history:
- Notice repeated informal patterns?
- Create custom rules for them
- Build your personal rule library

---

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Open Settings | ⌘, |
| Navigate to Dictionary | (Click in sidebar) |
| Clear test input | (Click "Clear" button) |

---

## Privacy & Performance

### Privacy

- ✅ **100% local processing** - Nothing sent to servers
- ✅ **No internet required** - Works completely offline
- ✅ **No data collection** - Rules stored locally only
- ✅ **No AI calls** - Independent of AI providers

### Performance

- **Processing time:** <1ms per transcription
- **Memory usage:** Negligible (<1KB)
- **Battery impact:** Minimal (simple regex operations)
- **Storage:** ~10KB for default rules

---

## FAQ

### Q: Do Quick Rules work without AI enhancement?
**A:** Yes! Quick Rules are completely independent. You can use them alone for instant cleanup without any AI.

### Q: Can I use Quick Rules with any AI provider?
**A:** Yes. Quick Rules process text before it goes to any AI provider (Ollama, OpenAI, etc.).

### Q: Will Quick Rules slow down transcription?
**A:** No. Processing takes less than 1ms and happens instantly after transcription completes.

### Q: Can I export/import my custom rules?
**A:** Not yet, but this is a planned feature. Currently rules are stored in UserDefaults.

### Q: Do rules apply to existing transcriptions?
**A:** No. Rules only apply to new transcriptions. Use the "Retry Transcription" feature to reprocess with current rules.

### Q: Can I disable Quick Rules temporarily?
**A:** Yes. Just toggle the master "Enable" switch off. Rules remain configured for when you enable again.

### Q: Will Quick Rules change transcription accuracy?
**A:** No. Quick Rules process the transcribed text after transcription is complete. They don't affect the speech recognition itself.

### Q: Can I share my custom rules?
**A:** Currently manual only - you can share screenshots or text descriptions. Rule export/import is planned for future.

---

## Examples by Use Case

### Use Case 1: Student Notes

**Goal:** Clean up lecture transcriptions quickly

**Setup:**
- Quick Rules: Enable "Casual to Formal", "Duplicates", "Spacing"
- AI Enhancement: OFF (speed priority)

**Result:**
- Instant processing
- Professional enough for studying
- Can transcribe entire lectures without delays

### Use Case 2: Professional Emails

**Goal:** High-quality business communication

**Setup:**
- Quick Rules: Enable all except "Filler Words"
- Word Replacements: Company-specific terms
- AI Enhancement: ON with "professional email" prompt

**Result:**
- Clean input for AI (faster processing)
- Consistent terminology
- Polished, professional output

### Use Case 3: Creative Writing

**Goal:** Natural dialogue with occasional cleanup

**Setup:**
- Quick Rules: Enable "Duplicates" and "Spacing" only
- AI Enhancement: ON with creative prompts

**Result:**
- Preserves casual voice and contractions
- Fixes only obvious errors
- AI has natural text to work with

### Use Case 4: Code Documentation

**Goal:** Technical accuracy with proper formatting

**Setup:**
- Quick Rules: Enable "Spacing", custom rules for tech terms
- Word Replacements: API names, function names
- AI Enhancement: ON with "technical documentation" prompt

**Result:**
- Proper spacing for code readability
- Consistent technical terminology
- AI-enhanced explanations

---

## Version History

### v1.0 (December 7, 2025)
- Initial implementation
- 17 preset rules across 5 categories
- Live preview feature
- Custom rule creation
- Category organization
- Integration with Word Replacement and AI Enhancement

---

## Support & Feedback

For issues, suggestions, or questions:

1. **GitHub Issues:** [Your repository URL]
2. **Documentation:** See QUICK_RULES_IMPLEMENTATION.md for technical details
3. **Community:** Share your custom rules and use cases!

---

## Summary

Quick Rules provide a **fast, predictable, and privacy-focused** way to clean up transcribed text. They work perfectly **alone for basic cleanup** or **in combination with AI enhancement** for high-quality output.

**Key Takeaways:**

✨ **Instant** - No delays, no API calls  
✨ **Predictable** - Same input = same output  
✨ **Private** - 100% local processing  
✨ **Flexible** - Use alone or with AI  
✨ **Customizable** - Create your own rules  

Start with default settings, test with your speaking style, and adjust as needed. Happy transcribing!

---

**Last Updated:** December 7, 2025  
**Author:** VoiceInk Community  
**License:** GPL v3
