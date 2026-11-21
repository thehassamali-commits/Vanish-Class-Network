# Vanish Relay Protocol v1

**Status: Approved by the class**  
**Relay:** `wss://vanish-relay-sawaira.bonto.page/ws`  
**Transport:** WebSocket, JSON text frames  
**Protocol version:** `1`  
**Wire timestamps:** Unix epoch milliseconds

## 1. Join

The app sends:

```json
{"type":"join","protocol":1,"device_id":"<unique id>","name":"Student"}
```

The relay replies:

```json
{"type":"welcome","protocol":1,"server_time":1794839291139}
```

The display name is required and must contain 1–30 characters.

## 2. Send a message

The app sends a flat JSON object:

```json
{"type":"message","id":"<unique id>","sender":"Student","text":"Hello"}
```

Message text must contain 1–500 characters. The app includes its joined display name as `sender`, but the relay uses the name from JOIN as authoritative. The relay assigns `sent_at` and `expires_at` (`sent_at + 30000`). Clients do not send `device_id` or timestamps in this packet.

## 3. Receive a message

The relay broadcasts to all joined apps, including the sender:

```json
{"type":"message","id":"...","sender":"Student","text":"Hello","sent_at":1794839366594,"expires_at":1794839396594}
```

## 4. Delivered

The relay sends only to the sender:

```json
{"type":"delivered","id":"...","count":2}
```

`count` is the number of joined apps that received the message. There is no client-to-relay `delivered` packet in v1.

## 5. Expired

The relay broadcasts after 30 seconds:

```json
{"type":"expired","id":"..."}
```

Apps remove the message on this event or when its adjusted expiry deadline passes.

## 6. Heartbeat

The app sends `{"type":"ping"}` every 15 seconds. The relay replies `{"type":"pong"}`. If no pong arrives for 30 seconds, the app closes the socket and reconnects.

## 7. Reconnect

Reconnect delays are 1, 2, 4, then 8 seconds; subsequent retries wait 8 seconds. The relay replays no messages after rejoining.

## 8. Duplicates

The relay ignores a message ID it still holds. Apps keep IDs they have seen and ignore repeats.

## 9. Clock offset

On `welcome`, the app computes:

```text
offset = server_time - phone_time
countdown = (expires_at - offset) - phone_time
```

All values in this calculation are milliseconds. The Flutter client converts wire timestamps to seconds only for its existing local SQLite representation; it calculates the same adjusted server-time deadline.

## 10. Errors

```json
{"type":"error","code":"...","message":"..."}
```

Codes: `bad_json`, `bad_protocol`, `bad_name`, `not_joined`, `bad_message`, `unknown_type`.

## 11. Storage and offline queue

The relay keeps messages in memory only and deletes them at `expires_at`. The app may queue an outgoing message locally while disconnected, but drops it if its local 30-second queue deadline passes before it can be sent. The relay does not know about the offline queue. After reconnect, the app sends only unexpired queued messages. The relay does not replay earlier messages.


## 12. Presence (relay -> all joined apps)

The relay broadcasts a presence update whenever a user joins or leaves.

Example:

```json
{"type":"presence","count":3,"members":["Sawaira","Ali","Sara"]}
```

- `count` represents the current number of joined apps.
- `members` contains the display names of joined users in join order.
- The relay sends this update to all currently joined apps.
- Apps that do not recognize this message type can safely ignore it.


## Notes

- `device_id` is sent by apps but the relay does not use it yet.
- The relay has no password. Anyone with the address can join.
- The free host may sleep while idle; the first connection after a pause can take up to a minute.
- This project uses the class-approved relay as a client. The separate Python server included in this repository is the earlier local starter server and is not the class-wide Protocol v1 relay.
