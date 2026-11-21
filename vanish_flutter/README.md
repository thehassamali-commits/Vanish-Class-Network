
# Vanish Class Network - Flutter Client

This directory contains the Flutter Android application for Vanish Class Network.

## Features

- Join the shared class relay using a display name.
- Send and receive class messages.
- Automatically remove messages after 30 seconds.
- Synchronize countdown timing with the relay.
- Queue outgoing messages temporarily when offline.
- Discard queued messages after their local expiry deadline.
- Prevent duplicate messages using unique IDs.
- Reconnect automatically after disconnection.
- Store messages locally using SQLite.

## Requirements

- Flutter SDK
- Android Studio
- Android device or emulator
- Internet connection

## Setup

Install dependencies:

```bash
flutter pub get
```

Check connected devices:

```bash
flutter devices
```

Run:

```bash
flutter run
```

Build a release APK:

```bash
flutter build apk --release
```

## Relay Configuration

The default relay address is configured in `lib/main.dart`.

The application uses:

`wss://vanish-relay-sawaira.bonto.page/ws`

## Protocol

See the repository's root `PROTOCOL.md` file for the communication protocol.

## Author

Hassam Ali
