-- Query statistics for diagnosing the bottleneck (stage 3).
-- Requires shared_preload_libraries=pg_stat_statements, set in docker-compose.yml.
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
