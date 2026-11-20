const CREDENTIAL_TTL_SECONDS = 2 * 60 * 60;
const PROVIDER_TIMEOUT_MS = 1800;

// Only retain the documented browser transports, including TLS on port 443.
const stunUrl = /^stun:stun\.cloudflare\.com:3478$/;
const turnUrl = /^(?:turn:turn\.cloudflare\.com:(?:3478\?transport=(?:udp|tcp)|443\?transport=udp|80\?transport=tcp)|turns:turn\.cloudflare\.com:(?:443|5349)\?transport=tcp)$/;
const tlsPrimary = "turns:turn.cloudflare.com:5349?transport=tcp";
const tlsAlternate = "turns:turn.cloudflare.com:443?transport=tcp";
const fetchErrorNames = new Set(["TypeError", "NetworkError", "AbortError", "TimeoutError"]);

function browserIceServers(entries) {
  if (!Array.isArray(entries)) return [];
  const servers = [];
  for (const entry of entries.slice(0, 8)) {
    if (!entry || typeof entry !== "object") continue;
    const urls = (Array.isArray(entry.urls) ? entry.urls : [entry.urls])
      .slice(0, 16).filter(url => typeof url === "string" && url.length < 160);
    const stun = urls.filter(url => stunUrl.test(url));
    const turn = urls.filter(url => turnUrl.test(url));
    if (stun.length) servers.push({ urls: stun });
    if (turn.length && [entry.username, entry.credential].every(value =>
      typeof value === "string" && value.length > 0 && value.length <= 512)) {
      if (turn.includes(tlsPrimary) && !turn.includes(tlsAlternate)) turn.push(tlsAlternate);
      servers.push({ urls: turn, username: entry.username, credential: entry.credential });
    }
  }
  return servers.some(server => server.credential) ? servers : [];
}

function unavailable(env, stage, details = {}) {
  return { relay_status: { stage, id32: env.TURN_KEY_ID?.length === 32,
    token64: env.TURN_KEY_API_TOKEN?.length === 64, ...details } };
}

async function mintCredentials(env) {
  const url = `https://rtc.live.cloudflare.com/v1/turn/keys/${encodeURIComponent(env.TURN_KEY_ID)}/credentials/generate-ice-servers`;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), PROVIDER_TIMEOUT_MS);
  let receivedHeaders = false;
  try {
    const response = await fetch(url, {
      method: "POST", redirect: "manual", signal: controller.signal,
      headers: { Authorization: `Bearer ${env.TURN_KEY_API_TOKEN}`, "Content-Type": "application/json" },
      body: JSON.stringify({ ttl: CREDENTIAL_TTL_SECONDS }),
    });
    receivedHeaders = true;
    if (!response.ok) return unavailable(env, "upstream_http", { code: response.status });
    const servers = browserIceServers((await response.json())?.iceServers);
    return servers.length ? { ice_servers: servers } : unavailable(env, "upstream_shape");
  } catch (error) {
    if (controller.signal.aborted || error?.name === "TimeoutError") return unavailable(env, "upstream_timeout");
    if (receivedHeaders) return unavailable(env, "upstream_shape");
    const error_name = fetchErrorNames.has(error?.name) ? error.name : "Other";
    return unavailable(env, "upstream_fetch", { error_name });
  } finally {
    clearTimeout(timeout);
  }
}

export async function admissionIceServers(env, code, peerId, tokenHash) {
  if (!env.TURN_KEY_ID || !env.TURN_KEY_API_TOKEN) return unavailable(env, "bindings_absent");
  let stage = "storage_claim";
  try {
    const now = Math.floor(Date.now() / 1000);
    const claim = crypto.randomUUID();
    // A lease covers simultaneous retries on different Worker instances. The
    // peer foreign key drops the temporary credentials when the seat is freed.
    const owner = await env.DB.prepare(`INSERT INTO webrtc_turn_grants
      (code, peer_id, token_hash, key_id, claim, usable_until, servers)
      SELECT code, peer_id, token_hash, ?4, ?5, ?6, NULL FROM webrtc_peers
        WHERE code=?1 AND peer_id=?2 AND token_hash=?3 AND expires_at>?7
      ON CONFLICT(code, peer_id) DO UPDATE SET token_hash=excluded.token_hash,
        key_id=excluded.key_id, claim=excluded.claim, usable_until=excluded.usable_until, servers=NULL
      WHERE token_hash != ?3 OR key_id != ?4 OR usable_until <= ?7
      RETURNING claim`).bind(code, peerId, tokenHash, env.TURN_KEY_ID, claim, now + 5, now).first();
    if (!owner) {
      stage = "storage_read";
      for (const delay of [0, 150, 350, 650, 950]) {
        if (delay) await new Promise(resolve => setTimeout(resolve, delay));
        const row = await env.DB.prepare(`SELECT servers FROM webrtc_turn_grants
          WHERE code=?1 AND peer_id=?2 AND token_hash=?3 AND key_id=?4`)
          .bind(code, peerId, tokenHash, env.TURN_KEY_ID).first();
        if (!row) return unavailable(env, "claim_stale");
        if (row.servers !== null) {
          const servers = browserIceServers(JSON.parse(row.servers));
          return servers.length ? { ice_servers: servers } : unavailable(env, "cached_unavailable");
        }
      }
      return unavailable(env, "grant_pending");
    }
    const result = await mintCredentials(env);
    const servers = result.ice_servers || [];
    const usableUntil = now + (servers.length ? CREDENTIAL_TTL_SECONDS - 60 : 10);
    stage = "storage_save";
    const current = await env.DB.prepare(`UPDATE webrtc_turn_grants SET servers=?1, usable_until=?2
      WHERE code=?3 AND peer_id=?4 AND claim=?5 RETURNING claim`)
      .bind(JSON.stringify(servers), usableUntil, code, peerId, claim).first();
    return current ? result : unavailable(env, "claim_stale");
  } catch {
    return unavailable(env, stage);
  }
}
