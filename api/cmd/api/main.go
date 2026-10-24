package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"napkinlab/api/internal/cache"
	"napkinlab/api/internal/handlers"
	"napkinlab/api/internal/storage"
)

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func envInt(key string, def int) int {
	n, err := strconv.Atoi(env(key, ""))
	if err != nil {
		return def
	}
	return n
}

// envDuration accepts both "3600s" and plain seconds "3600".
func envDuration(key string, def time.Duration) time.Duration {
	v := env(key, "")
	if d, err := time.ParseDuration(v); err == nil {
		return d
	}
	if n, err := strconv.Atoi(v); err == nil {
		return time.Duration(n) * time.Second
	}
	return def
}

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	store, err := storage.New(ctx, env("DATABASE_URL", "postgres://napkin:napkin@localhost:5432/napkin"), int32(envInt("DB_POOL", 10)))
	if err != nil {
		log.Error("postgres", "err", err)
		os.Exit(1)
	}
	defer store.Close()

	c := cache.New(env("REDIS_ADDR", "localhost:6379"), envDuration("CACHE_TTL", time.Hour))
	defer c.Close()

	status := envInt("REDIRECT_STATUS", http.StatusFound)
	if status != http.StatusMovedPermanently && status != http.StatusFound {
		status = http.StatusFound
	}

	srv := handlers.New(handlers.Config{
		BaseURL:        env("BASE_URL", "http://localhost:8080"),
		RedirectStatus: status,
		CacheOn:        env("CACHE", "off") == "on",
		LogRequests:    env("LOG_REQUESTS", "off") == "on",
	}, store, c, log)

	httpSrv := &http.Server{Addr: ":8080", Handler: srv.Routes(), ReadHeaderTimeout: 5 * time.Second}
	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = httpSrv.Shutdown(shutdownCtx)
	}()

	log.Info("listening", "addr", httpSrv.Addr, "redirect_status", status, "cache", env("CACHE", "off"))
	if err := httpSrv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Error("http", "err", err)
		os.Exit(1)
	}
}
