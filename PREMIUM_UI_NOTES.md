# Vanish Premium UI update

This update refreshes the Flutter presentation while preserving the approved Vanish Relay Protocol v1 communication logic.

## Included
- Branded premium join screen
- Redesigned chat header, connection status and empty state
- Updated message bubbles with a 30-second countdown/progress indicator
- Redesigned message composer
- Three persisted appearance themes: Midnight Violet, Pearl Light and Emerald
- Theme can be changed using the palette icon on the join and chat screens

## Important
The relay URL, JSON protocol, WebSocket handling, SQLite message store, expiry logic, heartbeat and reconnect behavior were not intentionally changed in this UI update.

## Run
From `vanish_flutter`:

```powershell
flutter clean
flutter pub get
flutter run -d <your-device-id>
```
