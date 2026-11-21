import asyncio, json, time
from typing import Dict, Set
from fastapi import APIRouter, WebSocket, WebSocketDisconnect

router = APIRouter()
# In-memory only. Do not log message text or persist it.
active: Dict[str, dict] = {}
seen_ids = set()  # IDs only; no expired message content is retained.
clients: Set[WebSocket] = set()
lock = asyncio.Lock()
TTL = 30

async def send(ws, payload):
    await ws.send_text(json.dumps(payload, separators=(",", ":")))

async def broadcast(payload):
    async with lock:
        peers = list(clients)
    dead = []
    for peer in peers:
        try:
            await send(peer, payload)
        except Exception:
            dead.append(peer)
    if dead:
        async with lock:
            for peer in dead:
                clients.discard(peer)

async def expire_message(mid, deadline):
    try:
        await asyncio.sleep(max(0, deadline - time.time()))
        entry = active.get(mid)
        if entry and entry["message"]["expires_at"] <= time.time():
            active.pop(mid, None)
            await broadcast({"type":"expired","id":mid,"expires_at":deadline,"server_time":time.time()})
    except asyncio.CancelledError:
        pass

@router.websocket("/ws/chat")
async def chat(ws: WebSocket):
    await ws.accept()
    async with lock:
        clients.add(ws)
    try:
        while True:
            try:
                packet = json.loads(await ws.receive_text())
            except json.JSONDecodeError:
                await send(ws, {"type":"error","message":"Invalid JSON"})
                continue
            kind = packet.get("type")
            if kind == "join":
                await send(ws, {"type":"joined","name":str(packet.get("name","Student"))[:40],
                    "device_id":str(packet.get("device_id",""))[:100],
                    "server_time":time.time(),"protocol":"vanish-v1"})
            elif kind == "send":
                raw = packet.get("message") or {}
                mid = str(raw.get("id",""))[:100]
                body = str(raw.get("text",""))[:2000]
                if not mid or not body.strip():
                    await send(ws, {"type":"error","message":"Message id and text are required"})
                    continue
                if mid in seen_ids:
                    await send(ws, {"type":"duplicate","id":mid})
                    continue
                now = time.time()
                msg = {"id":mid,"sender":str(raw.get("sender","Student"))[:40],
                    "device_id":str(raw.get("device_id",""))[:100],"text":body,
                    "sent_at":now,"expires_at":now+TTL}
                task = asyncio.create_task(expire_message(mid, now+TTL))
                active[mid] = {"message":msg,"task":task}
                seen_ids.add(mid)
                await broadcast({"type":"message","message":msg,"server_time":time.time()})
            elif kind == "delivered":
                mid = str(packet.get("id",""))
                if mid in active and active[mid]["message"]["expires_at"] > time.time():
                    await broadcast({"type":"delivered","id":mid,
                        "device_id":str(packet.get("device_id",""))[:100],"server_time":time.time()})
            elif kind == "heartbeat":
                await send(ws, {"type":"heartbeat_ack","server_time":time.time()})
            else:
                await send(ws, {"type":"error","message":"Unknown event type"})
    except WebSocketDisconnect:
        pass
    finally:
        async with lock:
            clients.discard(ws)
