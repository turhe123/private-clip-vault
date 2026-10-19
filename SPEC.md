# PrivateClipVault — specification

**Tagline:** A clipboard history that skips secrets, expires old items, and keeps everything encrypted on your Mac.

**Category:** Clipboard

**Inspired by (paid):** CopyClip 2 ($7.99 one-time)

**Frameworks:** SwiftUI, AppKit, CryptoKit, Security, ServiceManagement, LocalAuthentication

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

What the paid app does and evidence of demand. CopyClip 2 is a simple menu bar clipboard history sold for 7.99 dollars with a free trial, and it appears in many best clipboard manager comparisons for people who want something plain and dependable. Our research did not find a mainstream tool centered on privacy, so our clean-room version, PrivateClipVault, takes the same simple history idea and makes privacy its defining trait: sensitive items are filtered, history expires on its own, and the storage is encrypted.

Feature set. The app records text copied from any app into a short history, default 50 entries. It detects probable secrets and either skips them or stores them only briefly. Detection rules include the concealed pasteboard type used by password managers, strings that look like credit card numbers passing a Luhn check, long random-looking tokens of 32 or more characters without spaces, and strings beginning with common key prefixes. Each entry has a time to live, set globally to one of 1 minute, 5 minutes, 1 hour, 1 day, or never, with a shorter fixed 30 second lifetime for items flagged as sensitive if the user chooses to keep them. History is encrypted at rest with a symmetric key held in the keychain. Optional lock: viewing history requires Touch ID or the account password via LocalAuthentication. An ignored apps list prevents capture from chosen apps. Selecting an entry copies it back to the pasteboard, and a Pause Capture switch stops all recording.

UI spec. The app is a MenuBarExtra with a padlock icon that changes to an open padlock while unlocked. The menu lists the last ten entries with a truncated preview, a small clock icon showing remaining lifetime on entries that expire, and sensitive entries displayed as dots until hovered. Below are Show All, Pause Capture, Clear Everything, Settings, and Quit. Show All opens a window with a searchable list. Empty state: History is empty, copy something to get started. Locked state: a centered Unlock button. Settings fields: history size, lifetime picker, skip detected secrets toggle, require authentication toggle, ignored apps list, and Launch at login.

Technical approach. Poll NSPasteboard.general.changeCount at 0.5 second intervals, and use NSWorkspace to find the frontmost app at copy time. Serialize entries to JSON, encrypt with CryptoKit AES.GCM using a 256-bit key stored as a generic password item through the Security framework, and write the sealed box to a file in Application Support. Authentication uses LAContext evaluatePolicy with deviceOwnerAuthentication and a reason string, and the unlocked state times out after 60 seconds of inactivity. A background timer every 15 seconds purges expired entries and rewrites the file. Luhn and token heuristics are plain Swift functions. No special privacy permissions are needed beyond keychain access for the app itself. Launch at login uses SMAppService.mainApp.

Edge cases and error handling. If the keychain item is missing or the file cannot be decrypted, show a message offering to reset the vault, never crash. If biometrics are unavailable, fall back to the account password automatically. Do not log clipboard content anywhere, including debug output. Clear the in-memory list when the screen locks, observed through the distributed screen locked notification. Make sure expired items are truly removed from disk on the next write. Cap entries at 100 kilobytes each. A privacy note in settings clearly states that nothing leaves the Mac.
