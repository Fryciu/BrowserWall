# BrowserWall

[![Flutter](https://img.shields.io/badge/Platform-Flutter-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Language-Dart-0175C2?logo=dart)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

The first web browser dedicated to eliminating digital distractions.

## 🛡️ Security & Filtering
Content Filter (SafeSearch): Built-in mechanism to block adult content, designed to maintain focus during deep work or serve as a robust parental control tool.

Integrated AdBlock: It is not as good as fe. Ublock Origin, but it's something

Domain Blacklist: Custom blocking of specific domains or keywords to prevent access to distracting websites.

Word Blocklist: Block words which lead you to bad content.

Translate Bypass Prevention: If you write the word in one language, it's linguistic counterparts are blocked as well.

Typo Bypass Prevention: Words are checked using Levenstein length and normalization. If this is a problem (fe. it gets a word it's not supposed to) the maximum length of particular translations can be modified after giving a password.

## 🔐 Privacy & Control
Password Protection: Secure your filtering settings with a password to prevent unauthorized configuration changes.

History Management: Streamlined access to browsing history with quick-clear options to maintain privacy.

## ✨ User Experience
Home Screen Shortcuts: Instant access to your most-visited websites directly from the browser's dashboard.

Intuitive Settings UI: A modern control panel that puts all filtering and security options just one click away.


## 🛠 Tech Stack
Framework: Flutter (Dart)

WebView Engine: flutter_inappwebview

State Management: Ephemeral State (setState) — Optimized for low memory overhead and high performance in a single-view architecture.

Persistence: shared_preferences for blacklist and security configurations.

## 🚧 Current plans
- I'm planning on testing this browser and if for a month there are no challenges in using it, then I'll implement the english language into it.
- Adding icons for browsers
- Testing adding custom browsers as main ones.
- Defragmentation of files (3100 lines is too much)
