# ClaudeQuick

A lightweight macOS desktop app for chatting with Claude. Fast, native, no browser required.

![ClaudeQuick Screenshot](https://github.com/davidlifschitz/ClaudeQuick/raw/master/screenshot.png)

## Features

- Native SwiftUI macOS app
- Auto-connects via your existing **Claude Pro subscription** (no API key needed if you have Claude Code installed)
- Conversation history persisted locally with SQLite
- Token usage shown per message
- Sidebar with searchable conversation list

## Requirements

- macOS 12 or later
- Either:
  - [Claude Code](https://claude.ai/code) installed and logged in (uses your Pro subscription automatically), or
  - An [Anthropic API key](https://console.anthropic.com)

## Install

**Option 1 — Build and install (recommended)**

```bash
git clone https://github.com/davidlifschitz/ClaudeQuick.git
cd ClaudeQuick
./install.sh
```

This builds a release binary, assembles `ClaudeQuick.app`, installs it to `/Applications`, and registers it with Spotlight.

**Option 2 — Run from source**

```bash
swift run
```

## First launch

If you have Claude Code installed and logged in, the app auto-detects your credentials and skips onboarding entirely — just open it and start chatting.

If not, you'll see an onboarding screen with two options:
- **Use Claude Pro Subscription** — connects via your Claude Code login
- **Use API Key** — paste a key from [console.anthropic.com](https://console.anthropic.com)

## After code changes

```bash
./install.sh
```

Rebuilds and reinstalls to `/Applications`.

## Models

Default model is **Haiku 4.5** (fast, reliable with Pro subscription rate limits).  
Switch to Sonnet 4.6 or Opus 4.8 in Settings (gear icon, top right).

## Tech stack

- SwiftUI + AppKit (macOS 12+)
- SQLite via FMDB for local storage
- Anthropic Messages API
- macOS Keychain for credential storage
