// Package storage keeps short URLs in PostgreSQL.
package storage

import (
	"context"
	"errors"
	"sync/atomic"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"napkinlab/api/internal/base62"
)

// ErrNotFound is returned when no row matches the code.
var ErrNotFound = errors.New("not found")

type Store struct {
	pool    *pgxpool.Pool
	waiting atomic.Int64
}

// PoolStats is a snapshot of the connection pool for /metrics.
type PoolStats struct {
	AcquireWaitMs int64 // cumulative time spent acquiring connections
	Waiting       int64 // goroutines waiting for a connection right now
	InUse         int32 // connections currently checked out
}

func New(ctx context.Context, dsn string, poolSize int32) (*Store, error) {
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, err
	}
	cfg.MaxConns = poolSize
	cfg.MinConns = poolSize
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, err
	}
	return &Store{pool: pool}, nil
}

func (s *Store) Close() { s.pool.Close() }

func (s *Store) Ping(ctx context.Context) error { return s.pool.Ping(ctx) }

func (s *Store) Stats() PoolStats {
	st := s.pool.Stat()
	return PoolStats{
		AcquireWaitMs: st.AcquireDuration().Milliseconds(),
		Waiting:       s.waiting.Load(),
		InUse:         st.AcquiredConns(),
	}
}

// acquire checks out a connection and tracks how many callers are queued for one.
func (s *Store) acquire(ctx context.Context) (*pgxpool.Conn, error) {
	s.waiting.Add(1)
	defer s.waiting.Add(-1)
	return s.pool.Acquire(ctx)
}

// Create reserves an id from the sequence, derives the code from it and stores the row.
func (s *Store) Create(ctx context.Context, longURL string) (string, error) {
	conn, err := s.acquire(ctx)
	if err != nil {
		return "", err
	}
	defer conn.Release()

	var id int64
	if err := conn.QueryRow(ctx, "SELECT nextval('urls_id_seq')").Scan(&id); err != nil {
		return "", err
	}
	code := base62.Encode(id)
	_, err = conn.Exec(ctx,
		"INSERT INTO urls (id, code, long_url) VALUES ($1, $2, $3)", id, code, longURL)
	if err != nil {
		return "", err
	}
	return code, nil
}

// Lookup finds the long URL by code. There is no index on code, so this is a sequential scan.
func (s *Store) Lookup(ctx context.Context, code string) (string, error) {
	conn, err := s.acquire(ctx)
	if err != nil {
		return "", err
	}
	defer conn.Release()

	var longURL string
	err = conn.QueryRow(ctx, "SELECT long_url FROM urls WHERE code = $1 LIMIT 1", code).Scan(&longURL)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrNotFound
	}
	return longURL, err
}
