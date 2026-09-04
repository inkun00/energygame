CREATE TABLE IF NOT EXISTS rooms (
  code TEXT PRIMARY KEY,
  host_ip TEXT NOT NULL,
  port INTEGER NOT NULL CHECK (port BETWEEN 1024 AND 65535),
  token_hash TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_rooms_expires_at ON rooms (expires_at);
