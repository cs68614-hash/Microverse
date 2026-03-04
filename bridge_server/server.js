const http = require("http");

const PORT = Number(process.env.PORT || 8787);
const HOST = process.env.HOST || "127.0.0.1";

// In-memory queue: worldId -> pending actions[]
const worldActionQueues = new Map();

function readJsonBody(req) {
  return new Promise((resolve, reject) => {
    let body = "";
    req.on("data", (chunk) => {
      body += chunk;
      if (body.length > 1_000_000) {
        reject(new Error("Payload too large"));
        req.destroy();
      }
    });
    req.on("end", () => {
      if (!body) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(body));
      } catch (err) {
        reject(new Error("Invalid JSON body"));
      }
    });
    req.on("error", reject);
  });
}

function sendJson(res, statusCode, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(statusCode, {
    "Content-Type": "application/json",
    "Content-Length": Buffer.byteLength(body),
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type"
  });
  res.end(body);
}

function extractRoute(pathname) {
  const eventsMatch = pathname.match(/^\/v1\/worlds\/([^/]+)\/events:batch$/);
  if (eventsMatch) {
    return { type: "events_batch", worldId: decodeURIComponent(eventsMatch[1]) };
  }

  const pullMatch = pathname.match(/^\/v1\/worlds\/([^/]+)\/actions\/pull$/);
  if (pullMatch) {
    return { type: "actions_pull", worldId: decodeURIComponent(pullMatch[1]) };
  }

  return null;
}

// Placeholder for future OpenClaw main agent call integration.
function buildNpcResponseText(event) {
  const inputText = String(event.text || "").trim();
  if (!inputText) {
    return "[OpenClaw/mainplaceholder] Hello from the bridge.";
  }
  return `[OpenClaw/mainplaceholder] Received: ${inputText}`;
}

function enqueueAction(worldId, action) {
  const queue = worldActionQueues.get(worldId) || [];
  queue.push(action);
  worldActionQueues.set(worldId, queue);
}

function popAllActions(worldId) {
  const queue = worldActionQueues.get(worldId) || [];
  worldActionQueues.set(worldId, []);
  return queue;
}

async function handleEventsBatch(req, res, worldId) {
  let data;
  try {
    data = await readJsonBody(req);
  } catch (err) {
    sendJson(res, 400, { error: err.message });
    return;
  }

  const events = Array.isArray(data.events) ? data.events : [];

  for (const event of events) {
    if (!event || typeof event !== "object") {
      continue;
    }

    const isPlayerSaid = event.type === "player_said";
    const npcName = String(event.npc || "").trim().toLowerCase();
    if (!isPlayerSaid || npcName !== "alice") {
      continue;
    }

    enqueueAction(worldId, {
      npc: "alice",
      type: "say",
      text: buildNpcResponseText(event)
    });
  }

  sendJson(res, 200, {
    ok: true,
    worldId,
    accepted: events.length
  });
}

async function handleActionsPull(req, res, worldId) {
  try {
    // Drain body if present to keep endpoint tolerant of empty JSON posts.
    await readJsonBody(req);
  } catch (err) {
    sendJson(res, 400, { error: err.message });
    return;
  }

  const actions = popAllActions(worldId);
  sendJson(res, 200, {
    ok: true,
    worldId,
    actions
  });
}

const server = http.createServer(async (req, res) => {
  if (req.method === "OPTIONS") {
    sendJson(res, 204, {});
    return;
  }

  const url = new URL(req.url, `http://${req.headers.host || "localhost"}`);
  const route = extractRoute(url.pathname);

  if (!route) {
    sendJson(res, 404, { error: "Not found" });
    return;
  }

  if (req.method !== "POST") {
    sendJson(res, 405, { error: "Method not allowed" });
    return;
  }

  if (route.type === "events_batch") {
    await handleEventsBatch(req, res, route.worldId);
    return;
  }

  if (route.type === "actions_pull") {
    await handleActionsPull(req, res, route.worldId);
    return;
  }

  sendJson(res, 404, { error: "Not found" });
});

server.listen(PORT, HOST, () => {
  console.log(`[bridge_server] Listening on http://${HOST}:${PORT}`);
});
