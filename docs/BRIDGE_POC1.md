# Bridge POC-1 (single main agent -> one NPC, say-only)

This POC adds a Bridge server and a Godot bridge client path for `T` (start dialog):

- On `T` near an NPC, Microverse sends one `player_said` event to Bridge.
- Microverse immediately pulls actions.
- If Bridge returns a `say` action, Microverse shows a chat bubble on that NPC.

The old direct-LLM conversation path is still available behind a flag.

## 1) Start Bridge server

```bash
cd bridge_server
OPENCLAW_GATEWAY_TOKEN=04e3891c338d002fb507cddf8246b4a5 npm start
```

(`npm start` runs `node server.js`.)

Server defaults:
- Host: `127.0.0.1`
- Port: `8787`
- OpenClaw gateway URL: `http://127.0.0.1:12670` (`OPENCLAW_GATEWAY_URL`)
- OpenClaw token: no default (`OPENCLAW_GATEWAY_TOKEN` is required for OpenClaw calls)

Public endpoint:
- `https://api.techsong.dpdns.org/microverse-bridge`
- The Godot bridge client now uses this public HTTPS URL as its default base URL.

Optional:

```bash
HOST=0.0.0.0 PORT=8787 npm start
```

Example with explicit OpenClaw settings:

```bash
HOST=0.0.0.0 \
PORT=8787 \
OPENCLAW_GATEWAY_URL=http://127.0.0.1:12670 \
OPENCLAW_GATEWAY_TOKEN=04e3891c338d002fb507cddf8246b4a5 \
npm start
```

## 2) Run Microverse

Run the game as usual.

Bridge client is autoloaded at:
- `res://script/network/BridgeClient.gd`

Defaults:
- Base URL: `https://api.techsong.dpdns.org/microverse-bridge`
- World ID: `poc1-world`

Bridge mode flag (in `script/ai/DialogManager.gd`):
- `const USE_BRIDGE := true`
- Fallback player text (when no input dialog text is available): `Say something back to the player`

Set `USE_BRIDGE := false` to use the existing direct-LLM conversation path.

## 3) Endpoint behavior (POC)

- `POST /v1/worlds/:worldId/events:batch`
  - Accepts `{ "events": [...] }`
  - For an event like:
    - `{ "type": "player_said", "npc": "alice", "text": "..." }`
  - Calls OpenClaw gateway `POST /v1/chat/completions` with:
    - `Authorization: Bearer $OPENCLAW_GATEWAY_TOKEN`
    - `x-openclaw-agent-id: main`
    - `model: openclaw`
    - `user: microverse:{worldId}:alice` (stable per world/NPC session)
  - Enqueues one action from completion content:
    - `{ "npc": "alice", "type": "say", "text": "<openclaw content>" }`
  - If OpenClaw config/call fails, falls back to placeholder text and includes error details in the batch response under `errors`.

- `POST /v1/worlds/:worldId/actions/pull`
  - Returns and drains pending actions:
  - `{ "ok": true, "worldId": "...", "actions": [...] }`

No API key is required.
