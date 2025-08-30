PRAGMA foreign_keys=ON;

CREATE TABLE IF NOT EXISTS reports(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  content_id TEXT NOT NULL,
  reporter_id TEXT NOT NULL,
  reason TEXT,
  ts DATETIME DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(content_id, reporter_id)
);
CREATE INDEX IF NOT EXISTS idx_reports_content ON reports(content_id);

CREATE TABLE IF NOT EXISTS flagged_content(
  content_id TEXT PRIMARY KEY,
  flagged_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
