# Changelog

## 1.0 — 2026-11-03

First release.

- Clipboard history for text and images, with the source application and age
  shown for every entry.
- Global shortcut (⌘⇧V by default, three other presets) opening a panel next to
  the pointer.
- Filter as you type, ignoring case and accents.
- Paste with ⏎, with ⌘1–⌘9, or by clicking.
- Pin entries so they stay on top and survive eviction.
- Deduplication: copying something already in the history moves it back to the
  top instead of adding a second copy.
- Entries flagged `org.nspasteboard.ConcealedType` by password managers are
  never recorded.
- Launch at login, and a configurable history size from 10 to 100 entries.
- French and English, following the system language.
- Universal binary, Apple silicon and Intel.
