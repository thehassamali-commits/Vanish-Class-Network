
# Vanish Class Network

A Flutter-based class messaging application where messages automatically disappear 30 seconds after delivery.

## Project Overview

Vanish Class Network allows students to communicate through a shared class relay. Messages are distributed to joined devices and automatically expire after 30 seconds.

The application is built with Flutter and uses WebSocket communication, SQLite storage and local message expiry management.

## Main Features

- Shared class messaging through a WebSocket relay.
- Automatic 30-second message expiry.
- Server timestamp synchronization for accurate countdowns.
- Offline message queue with a local 30-second deadline.
- Duplicate message detection using unique message IDs.
- Automatic reconnection after connection loss.
- Local SQLite message storage and expiry cleanup.
- Multiple application themes.

## Technology Stack

- Flutter and Dart
- WebSocket communication
- JSON protocol
- SQLite using sqflite
- SharedPreferences
- UUID for unique message identifiers

## Repository Structure

```text
Vanish-Class-Network/
│
├── README.md
├── PROTOCOL.md
├── API_SPEC_VANISH_PROPOSAL.md
├── PREMIUM_UI_NOTES.md
│
└── vanish_flutter/
    ├── android/
    ├── lib/
    ├── test/
    ├── pubspec.yaml
    ├── pubspec.lock
    └── README.md
```

## Class Relay

The Flutter application uses the class-approved Protocol v1 relay:

`wss://vanish-relay-sawaira.bonto.page/ws`

All participating devices must use the same relay address and compatible protocol.

## Getting Started

### Requirements

- Flutter SDK
- Android Studio or another Flutter-compatible IDE
- Android device or emulator
- Internet connection

### Installation

Clone the repository:

```bash
git clone https://github.com/thehassamali-commits/Vanish-Class-Network.git
```

Open the Flutter project:

```bash
cd Vanish-Class-Network/vanish_flutter
```

Install dependencies:

```bash
flutter pub get
```

Check connected devices:

```bash
flutter devices
```

Run the application:

```bash
flutter run
```

### Build APK

```bash
flutter build apk --release
```

The generated APK is located at:

`build/app/outputs/flutter-apk/app-release.apk`

## Protocol

The application uses Protocol v1 with JSON messages transmitted through WebSocket connections.

The protocol defines joining, messaging, delivery notifications, expiry, heartbeat, reconnection, duplicate handling, clock synchronization, offline queue behaviour and the documented presence extension.

See [PROTOCOL.md](PROTOCOL.md) for the message formats and details.

## Testing

The project has been tested for two-device messaging, message countdown and expiry, and offline message delivery.

Further lifecycle and interoperability testing should be performed where applicable.

## Limitations

- Screenshots and external photography cannot be completely prevented.
- The relay may temporarily process message content.
- The relay is not password protected.
- The application does not provide end-to-end encryption.
- Offline devices cannot receive messages that expire before they reconnect.
- The hosted relay depends on its hosting provider's availability.

## AI Assistance

AI tools were used to assist with selected parts of development, debugging and documentation. The project should be understood and explained by its developer.

## Author

Hassam Ali

## Repository

https://github.com/thehassamali-commits/Vanish-Class-Network
