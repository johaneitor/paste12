-- Compatible Postgres
ALTER TABLE note ADD COLUMN IF NOT EXISTS author_fp TEXT;
-- Índice recomendado para feed (clave compuesta)
CREATE INDEX IF NOT EXISTS ix_note_ts_id ON note (timestamp DESC, id DESC);
