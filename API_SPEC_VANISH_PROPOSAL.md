# Vanish Relay Protocol v1

Status: **Approved by the class.** This file is retained at its original path for project history; the approved contract is documented in [`PROTOCOL.md`](PROTOCOL.md).

- Relay: `wss://vanish-relay-sawaira.bonto.page/ws`
- Transport: WebSocket, JSON text frames
- Version: `1`
- Timestamps: Unix epoch milliseconds

The Flutter client implementation follows the approved v1 message shapes, heartbeat, expiry, duplicate handling, reconnect schedule, and offline queue rule. The separate Python starter server remains the earlier `/ws/chat` implementation and is not the shared class relay.
