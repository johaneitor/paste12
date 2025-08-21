CREATE TABLE IF NOT EXISTS reports (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  content_id TEXT NOT NULL,
  reporter_id TEXT,
  reason TEXT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(content_id, reporter_id)
);
CREATE INDEX IF NOT EXISTS idx_reports_content ON reports(content_id);

-- Tabla opcional para marcar contenido al llegar al umbral
CREATE TABLE IF NOT EXISTS flagged_content (
  content_id TEXT PRIMARY KEY,
  flagged_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
