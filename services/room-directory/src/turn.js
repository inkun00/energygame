const CREDENTIAL_TTL_SECONDS = 2 * 60 * 60;
const PROVIDER_TIMEOUT_MS = 1800;

// Only retain the documented browser transports, including TLS on port 443.
const stunUrl = /^stun:stun\.cloudflare\.com:3478$/;
const turnUrl = /^(?:turn:turn\.cloudflare\.com:(?:3478\?transport=(?:udp|tcp)|443\?transport=udp|80\?transport=tcp)|turns:turn\.cloudflare\.com:(?:443|5349)\?transport=tcp)$/;

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
      servers.push({ urls: turn, username: entry.username, credential: entry.credential });
    }
  }
  return servers.some(server => server.credential) ? servers : [];
}

async function mintCredentials(env) {
  const url = `https://rtc.live.cloudflare.com/v1/turn/keys/${encodeURIComponent(env.TURN_KEY_ID)}/credentials/generate-ice-servers`;
  const response = await fetch(url, {
    method: "POST", redirect: "error", signal: AbortSignal.timeout(PROVIDER_TIMEOUT_MS),
    headers: { Authorization: `Bearer ${env.TURN_KEY_API_TOKEN}`, "Content-Type": "application/json" },
    body: JSON.stringify({ ttl: CREDENTIAL_TTL_SECONDS }),
  });
  if (!response.ok) return [];
  return browserIceServers((await response.json())?.iceServers);
}

export async function admissionIceServers(env, code, peerId, tokenHash) {
  if (!env.TURN_KEY_ID || !env.TURN_KEY_API_TOKEN) return {};
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
      for (const delay of [0, 150, 350, 650, 950]) {
        if (delay) await new Promise(resolve => setTimeout(resolve, delay));
        const row = await env.DB.prepare(`SELECT servers FROM webrtc_turn_grants
          WHERE code=?1 AND peer_id=?2 AND token_hash=?3 AND key_id=?4`)
          .bind(code, peerId, tokenHash, env.TURN_KEY_ID).first();
        if (!row) return {};
        if (row.servers !== null) {
          const servers = JSON.parse(row.servers);
          return servers.length ? { ice_servers: servers } : {};
        }
      }
      return {};
    }
    let servers = [];
    try { servers = await mintCredentials(env); } catch { /* Optional provider is unavailable. */ }
    const usableUntil = now + (servers.length ? CREDENTIAL_TTL_SECONDS - 60 : 10);
    const current = await env.DB.prepare(`UPDATE webrtc_turn_grants SET servers=?1, usable_until=?2
      WHERE code=?3 AND peer_id=?4 AND claim=?5 RETURNING claim`)
      .bind(JSON.stringify(servers), usableUntil, code, peerId, claim).first();
    return current && servers.length ? { ice_servers: servers } : {};
  } catch {
    return {};
  }
}
