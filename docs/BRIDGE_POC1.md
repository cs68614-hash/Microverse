# Bridge POC-1 (single main agent -> one NPC, say-only)

This POC adds a local Bridge server and a Godot bridge client path for `T` (start dialog):

- On `T` near an NPC, Microverse sends one `player_said` event to Bridge.
- Microverse immediately pulls actions.
- If Bridge returns a `say` action, Microverse shows a chat bubble on that NPC.

The old direct-LLM conversation path is still available behind a flag.

## 1) Start Bridge server

```bash
cd bridge_server
npm start
```

(`npm start` runs `node server.js`.)

Server defaults:
- Host: `127.0.0.1`
- Port: `8787`

Optional:

```bash
HOST=0.0.0.0 PORT=8787 npm start
```

## 2) Run Microverse

Run the game as usual.

Bridge client is autoloaded at:
- `res://script/network/BridgeClient.gd`

Defaults:
- Base URL: `http://127.0.0.1:8787`
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
  - Enqueues one action:
    - `{ "npc": "alice", "type": "say", "text": "[OpenClaw/mainplaceholder] ..." }`

- `POST /v1/worlds/:worldId/actions/pull`
  - Returns and drains pending actions:
  - `{ "ok": true, "worldId": "...", "actions": [...] }`

No API key is required.
