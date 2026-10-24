CREATE TABLE urls (
  id         BIGSERIAL PRIMARY KEY,
  code       TEXT NOT NULL,
  long_url   TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- ВАЖНО: индекса по code нет. Это намеренно: узкое место для стадии 3.
