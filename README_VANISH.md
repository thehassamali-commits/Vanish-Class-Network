# Vanish Class Network

This repository contains the Flutter client, the earlier local Python/Field Sync server, and the original Kotlin starter app. The class-approved chat client now targets **Vanish Relay Protocol v1**.

## Class relay (Protocol v1)

```text
wss://vanish-relay-sawaira.bonto.page/ws
```

The Flutter join screen uses this address by default. Leave it unchanged when testing with classmates. Enter a display name of 1–30 characters. All students must use the same relay address and the same approved protocol.

The Flutter client sends a v1 `join` packet, then flat `message` packets containing `id`, `sender`, and `text`. It handles `welcome`, `message`, `delivered`, `expired`, `pong`, and `error` responses; it sends `ping` every 15 seconds, reconnects with 1/2/4/8-second backoff, suppresses duplicate IDs, and uses the relay clock offset for relay-issued 30-second message expiry. Offline queued messages use a separate local 30-second queue deadline and are discarded if it passes before reconnect.

See [`PROTOCOL.md`](PROTOCOL.md) for the complete approved wire contract.

## Run the Flutter app on your Android phone

Open `vanish_flutter` in Android Studio. In the Android Studio Terminal, run:

```powershell
flutter pub get
flutter run -d 0472525064000141
```

Replace the device ID with the ID shown by `flutter devices` if testing on another phone. You can also select your connected device in Android Studio and press Run.

The phone needs internet access to reach the hosted `wss://` relay. The first connection after the free host has been idle may take up to a minute while it wakes. Keep the app open while testing.

## Local Python server

The `server/` directory contains the earlier local Field Sync / Vanish starter server. Its WebSocket route and message format are the old `/ws/chat` protocol; it is **not** the class-wide Protocol v1 relay. The updated Flutter app is configured for Sawaira's hosted v1 relay. Do not change the app's relay address to the local server if you want to communicate with classmates using Protocol v1.

The original Field Sync API and Kotlin starter project are preserved. The local server files have not been changed as part of the v1 client update.

## Current implementation notes

- The app keeps its existing UI and SQLite storage.
- Protocol timestamps are milliseconds on the wire; the app converts them to seconds for its existing database schema.
- The relay determines the sender name from JOIN. Protocol v1 message packets contain a sender name but no device ID; the relay treats the JOIN name as authoritative.
- Because v1 does not echo `device_id` in received message events, the app identifies its own echoed messages by their message IDs rather than by sender name.
- The app does not send a client `delivered` event; `delivered` is a relay-to-sender notification.
- The relay is not password protected and is not end-to-end encrypted. Do not send private or sensitive information.
- Live interoperability with the hosted relay still needs to be tested from two separate devices. A successful local Flutter build alone does not prove the relay is currently online or accepting v1 connections.

## Build an APK

```powershell
flutter build apk --release
```

The APK is generated at:

```text
build\app\outputs\flutter-apk\app-release.apk
```
