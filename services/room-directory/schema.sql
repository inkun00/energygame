CREATE TABLE IF NOT EXISTS rooms (
  code TEXT PRIMARY KEY,
  host_ip TEXT NOT NULL,
  port INTEGER NOT NULL CHECK (port BETWEEN 1024 AND 65535),
  token_hash TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_rooms_expires_at ON rooms (expires_at);

CREATE TABLE IF NOT EXISTS webrtc_rooms (
  code TEXT PRIMARY KEY,
  host_token_hash TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS webrtc_peers (
  code TEXT NOT NULL,
  peer_id INTEGER NOT NULL CHECK (peer_id BETWEEN 1 AND 4),
  token_hash TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  PRIMARY KEY (code, peer_id),
  FOREIGN KEY (code) REFERENCES webrtc_rooms(code) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS webrtc_signals (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  code TEXT NOT NULL,
  from_peer INTEGER NOT NULL,
  to_peer INTEGER NOT NULL,
  signal_type TEXT NOT NULL,
  payload TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (code) REFERENCES webrtc_rooms(code) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_webrtc_rooms_expires_at ON webrtc_rooms (expires_at);
CREATE INDEX IF NOT EXISTS idx_webrtc_peers_expiry ON webrtc_peers (code, expires_at);
CREATE INDEX IF NOT EXISTS idx_webrtc_signals_recipient ON webrtc_signals (code, to_peer, id);

CREATE TABLE IF NOT EXISTS webrtc_room_settings (
  code TEXT PRIMARY KEY REFERENCES webrtc_rooms(code) ON DELETE CASCADE,
  title TEXT NOT NULL,
  host_name TEXT NOT NULL,
  max_players INTEGER NOT NULL CHECK (max_players BETWEEN 2 AND 4),
  password_hash TEXT NOT NULL DEFAULT '',
  password_salt TEXT NOT NULL DEFAULT ''
);
