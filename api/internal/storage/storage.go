// Package storage keeps short URLs in PostgreSQL.
package storage

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"napkinlab/api/internal/base62"
)

// ErrNotFound is returned when no row matches the code.
var ErrNotFound = errors.New("not found")

type Store struct {
	pool *pgxpool.Pool
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

// Create reserves an id from the sequence, derives the code from it and stores the row.
func (s *Store) Create(ctx context.Context, longURL string) (string, error) {
	var id int64
	if err := s.pool.QueryRow(ctx, "SELECT nextval('urls_id_seq')").Scan(&id); err != nil {
		return "", err
	}
	code := base62.Encode(id)
	_, err := s.pool.Exec(ctx,
		"INSERT INTO urls (id, code, long_url) VALUES ($1, $2, $3)", id, code, longURL)
	if err != nil {
		return "", err
	}
	return code, nil
}

// Lookup finds the long URL by code. There is no index on code, so this is a sequential scan.
func (s *Store) Lookup(ctx context.Context, code string) (string, error) {
	var longURL string
	err := s.pool.QueryRow(ctx, "SELECT long_url FROM urls WHERE code = $1 LIMIT 1", code).Scan(&longURL)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrNotFound
	}
	return longURL, err
}
