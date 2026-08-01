CREATE TABLE IF NOT EXISTS workspace_items (
  id bigserial PRIMARY KEY,
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
