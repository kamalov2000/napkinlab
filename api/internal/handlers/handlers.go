// Package handlers wires HTTP endpoints to storage and cache.
package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"net/url"
	"sync/atomic"
	"time"

	"napkinlab/api/internal/cache"
	"napkinlab/api/internal/storage"
)

type Config struct {
	BaseURL        string
	RedirectStatus int
	CacheOn        bool
	LogRequests    bool
}

// Metrics are plain in-memory counters exposed by /metrics.
type Metrics struct {
	Requests    atomic.Int64
	Redirects   atomic.Int64
	CacheHits   atomic.Int64
	CacheMisses atomic.Int64
	DBErrors    atomic.Int64
}

type Server struct {
	cfg     Config
	store   *storage.Store
	cache   *cache.Cache
	log     *slog.Logger
	metrics Metrics
}

func New(cfg Config, store *storage.Store, c *cache.Cache, log *slog.Logger) *Server {
	return &Server{cfg: cfg, store: store, cache: c, log: log}
}

func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /shorten", s.shorten)
	mux.HandleFunc("GET /healthz", s.healthz)
	mux.HandleFunc("GET /metrics", s.metricsHandler)
	mux.HandleFunc("GET /{code}", s.redirect)
	return s.count(mux)
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

func (s *Server) count(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.metrics.Requests.Add(1)
		if !s.cfg.LogRequests {
			next.ServeHTTP(w, r)
			return
		}
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		s.log.Info("request", "method", r.Method, "path", r.URL.Path,
			"status", rec.status, "duration_ms", time.Since(start).Milliseconds())
	})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func (s *Server) shorten(w http.ResponseWriter, r *http.Request) {
	var req struct {
		URL string `json:"url"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8<<10)).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid json"})
		return
	}
	u, err := url.Parse(req.URL)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "url must be http or https"})
		return
	}
	code, err := s.store.Create(r.Context(), req.URL)
	if err != nil {
		s.metrics.DBErrors.Add(1)
		s.log.Error("create failed", "err", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "storage error"})
		return
	}
	writeJSON(w, http.StatusCreated, map[string]string{
		"code":      code,
		"short_url": s.cfg.BaseURL + "/" + code,
	})
}

func (s *Server) redirect(w http.ResponseWriter, r *http.Request) {
	code := r.PathValue("code")
	ctx := r.Context()

	if s.cfg.CacheOn {
		if longURL, ok, err := s.cache.Get(ctx, code); err == nil && ok {
			s.metrics.CacheHits.Add(1)
			s.metrics.Redirects.Add(1)
			http.Redirect(w, r, longURL, s.cfg.RedirectStatus)
			return
		}
		s.metrics.CacheMisses.Add(1)
	}

	longURL, err := s.store.Lookup(ctx, code)
	if errors.Is(err, storage.ErrNotFound) {
		http.NotFound(w, r)
		return
	}
	if err != nil {
		s.metrics.DBErrors.Add(1)
		http.Error(w, "storage error", http.StatusInternalServerError)
		return
	}
	if s.cfg.CacheOn {
		_ = s.cache.Set(ctx, code, longURL)
	}
	s.metrics.Redirects.Add(1)
	http.Redirect(w, r, longURL, s.cfg.RedirectStatus)
}

func (s *Server) healthz(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	if err := s.store.Ping(ctx); err != nil {
		http.Error(w, "postgres: "+err.Error(), http.StatusServiceUnavailable)
		return
	}
	if err := s.cache.Ping(ctx); err != nil {
		http.Error(w, "redis: "+err.Error(), http.StatusServiceUnavailable)
		return
	}
	fmt.Fprintln(w, "ok")
}

func (s *Server) metricsHandler(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	fmt.Fprintf(w, "requests_total %d\n", s.metrics.Requests.Load())
	fmt.Fprintf(w, "redirects_total %d\n", s.metrics.Redirects.Load())
	fmt.Fprintf(w, "cache_hits_total %d\n", s.metrics.CacheHits.Load())
	fmt.Fprintf(w, "cache_misses_total %d\n", s.metrics.CacheMisses.Load())
	fmt.Fprintf(w, "db_errors_total %d\n", s.metrics.DBErrors.Load())
	ps := s.store.Stats()
	fmt.Fprintf(w, "db_pool_acquire_wait_ms_total %d\n", ps.AcquireWaitMs)
	fmt.Fprintf(w, "db_pool_waiting %d\n", ps.Waiting)
	fmt.Fprintf(w, "db_pool_in_use %d\n", ps.InUse)
}
