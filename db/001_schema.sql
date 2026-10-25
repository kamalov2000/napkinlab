CREATE TABLE urls (
  id         BIGSERIAL PRIMARY KEY,
  code       TEXT NOT NULL,
  long_url   TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- IMPORTANT: there is no index on code. This is intentional: it is the bottleneck for stage 3.
