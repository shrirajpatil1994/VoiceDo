# VoiceDo

An iOS app that turns your voice into tasks and reminders — powered by Claude.

Tap the mic, speak naturally, and VoiceDo transcribes your words and uses Claude to parse your intent into structured to-dos, reminders, or message drafts. A home screen widget lets you capture tasks without even opening the app.

---

## Features

- **Voice capture** — record up to 60 seconds; iOS Speech Recognition transcribes in real time
- **AI intent parsing** — Claude (Sonnet) classifies and structures your spoken input into tasks, reminders, or message drafts
- **Offline fallback** — a local NLP parser handles intent when no API key is configured or Claude times out
- **Task & reminder management** — categorised to-dos with workspace support, completion tracking, and notification-based reminders
- **iOS widget** — quick-capture widget for the home/lock screen; syncs via App Group shared storage
- **Minimal capture mode** — lightweight UI triggered from the widget for one-tap voice entry

---

## Requirements

- iOS 17.0+
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Anthropic API key (optional — app works offline without one)

---

## Getting started

```bash
git clone https://github.com/shrirajpatil1994/VoiceDo.git
cd VoiceDo
xcodegen generate          # generates VoiceDo.xcodeproj from project.yml
open VoiceDo.xcodeproj
```

Build and run on a simulator or device. Add your Anthropic API key in **Settings → Claude API Key** — it is stored securely in the iOS Keychain.

---

## Configuration

| Setting | Where |
|---|---|
| Claude API key | Settings screen → stored in Keychain |
| Model | `claude-sonnet-4-6` (set in `AppConstants.claudeModel`) |
| API timeout | 8 seconds — falls back to offline parser on timeout |
| Max recording | 60 seconds |

---

## How it works

1. **Record** — `SpeechService` streams audio through `AVAudioEngine` and transcribes via `SFSpeechRecognizer`
2. **Parse** — `IntentParserService` runs an offline NLP pass first; if confidence < 0.8 and an API key is set, it calls Claude
3. **Claude call** — `ClaudeAPIService` sends the transcript to `claude-sonnet-4-6` and gets back structured JSON (`ParsedIntent`)
4. **Persist** — `PersistenceService` writes `TodoItem` or `ReminderItem` to a SwiftData store (SQLite in the App Group container)
5. **Widget sync** — `WidgetReloadService` writes a snapshot to shared UserDefaults and calls `WidgetCenter.shared.reloadAllTimelines()`

---

## Project structure

```
VoiceDo/
  App/                  App entry point and SwiftData model container
  Services/             ClaudeAPIService, SpeechService, PersistenceService,
                        IntentParserService, NotificationService, APIKeyManager
  Models/               TodoItem, ReminderItem, ParsedIntent, TaskCategory, Workspace
  Features/             SwiftUI screens — Dashboard, VoiceCapture, TodoList,
                        ReminderList, Settings, Onboarding, MinimalCapture
  Shared/               DeepLinkHandler, extensions, utilities
VoiceDoWidget/          Widget extension (timeline provider + views)
Packages/VoiceDoShared/ Shared Swift package — AppConstants, shared models
project.yml             XcodeGen config — edit this, not the .xcodeproj
```

---

## Permissions

VoiceDo requests the following at runtime:

| Permission | Purpose |
|---|---|
| Microphone | Recording voice input |
| Speech Recognition | Transcribing recorded audio |
| Notifications | Delivering reminders |
