// Package cache keeps code -> long_url pairs in Redis.
package cache

import (
	"context"
	"errors"
	"time"

	"github.com/redis/go-redis/v9"
)

type Cache struct {
	client *redis.Client
	ttl    time.Duration
}

func New(addr string, ttl time.Duration) *Cache {
	return &Cache{client: redis.NewClient(&redis.Options{Addr: addr}), ttl: ttl}
}

func (c *Cache) Close() error { return c.client.Close() }

func (c *Cache) Ping(ctx context.Context) error { return c.client.Ping(ctx).Err() }

// Get returns the cached long URL and whether it was found.
func (c *Cache) Get(ctx context.Context, code string) (string, bool, error) {
	v, err := c.client.Get(ctx, code).Result()
	if errors.Is(err, redis.Nil) {
		return "", false, nil
	}
	if err != nil {
		return "", false, err
	}
	return v, true, nil
}

func (c *Cache) Set(ctx context.Context, code, longURL string) error {
	return c.client.Set(ctx, code, longURL, c.ttl).Err()
}
