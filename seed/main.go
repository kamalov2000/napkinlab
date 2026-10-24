// Command seed bulk-loads N rows into urls via COPY and samples codes for k6.
package main

import (
	"context"
	"flag"
	"fmt"
	"math/rand/v2"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

const (
	alphabet  = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
	batchSize = 100_000
)

func base62(n int64) string {
	if n == 0 {
		return "0"
	}
	var buf [11]byte
	i := len(buf)
	for n > 0 {
		i--
		buf[i] = alphabet[n%62]
		n /= 62
	}
	return string(buf[i:])
}

// rows generates (id, code, long_url) for ids in [from, to).
type rows struct {
	next, to int64
}

func (r *rows) Next() bool { return r.next < r.to }

func (r *rows) Values() ([]any, error) {
	id := r.next
	r.next++
	return []any{id, base62(id), fmt.Sprintf("https://example.com/page/%d", id)}, nil
}

func (r *rows) Err() error { return nil }

func main() {
	n := flag.Int64("n", 1_000_000, "number of rows to insert")
	out := flag.String("out", "/results/sample_codes.txt", "file for sampled codes")
	sampleOnly := flag.Bool("sample-only", false, "only rewrite the sample file, insert nothing")
	flag.Parse()

	// SEED_SAMPLE sets how many random codes go to the sample file.
	sampleN := 20
	if v, err := strconv.Atoi(os.Getenv("SEED_SAMPLE")); err == nil && v > 0 {
		sampleN = v
	}

	ctx := context.Background()
	conn, err := pgx.Connect(ctx, os.Getenv("DATABASE_URL"))
	if err != nil {
		fail(err)
	}
	defer conn.Close(ctx)

	if !*sampleOnly {
		if err := seed(ctx, conn, *n); err != nil {
			fail(err)
		}
	}
	if err := sample(ctx, conn, sampleN, *out); err != nil {
		fail(err)
	}
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, "seed:", err)
	os.Exit(1)
}

func seed(ctx context.Context, conn *pgx.Conn, n int64) error {
	var start int64
	if err := conn.QueryRow(ctx, "SELECT COALESCE(MAX(id), 0) + 1 FROM urls").Scan(&start); err != nil {
		return err
	}
	end := start + n

	fmt.Printf("seeding %d rows (ids %d..%d)\n", n, start, end-1)
	began := time.Now()
	for from := start; from < end; from += batchSize {
		to := min(from+batchSize, end)
		_, err := conn.CopyFrom(ctx, pgx.Identifier{"urls"}, []string{"id", "code", "long_url"}, &rows{next: from, to: to})
		if err != nil {
			return err
		}
		fmt.Printf("  %d / %d  (%.1fs)\n", to-start, n, time.Since(began).Seconds())
	}
	if _, err := conn.Exec(ctx, "SELECT setval('urls_id_seq', $1)", end-1); err != nil {
		return err
	}
	if _, err := conn.Exec(ctx, "ANALYZE urls"); err != nil {
		return err
	}

	var total int64
	var size string
	err := conn.QueryRow(ctx,
		"SELECT count(*), pg_size_pretty(pg_total_relation_size('urls')) FROM urls").Scan(&total, &size)
	if err != nil {
		return err
	}
	fmt.Printf("done in %.1fs\n", time.Since(began).Seconds())
	fmt.Printf("rows:       %d\n", total)
	fmt.Printf("table size: %s\n", size)
	return nil
}

// sample picks random existing ids through the primary key: cheap even without an index on code.
func sample(ctx context.Context, conn *pgx.Conn, n int, out string) error {
	var maxID int64
	if err := conn.QueryRow(ctx, "SELECT COALESCE(MAX(id), 0) FROM urls").Scan(&maxID); err != nil {
		return err
	}
	if maxID == 0 {
		return fmt.Errorf("urls is empty, run `make seed` first")
	}
	ids := make([]int64, 0, n*2)
	for range n * 2 {
		ids = append(ids, rand.Int64N(maxID)+1)
	}
	res, err := conn.Query(ctx, "SELECT code FROM urls WHERE id = ANY($1) ORDER BY random() LIMIT $2", ids, n)
	if err != nil {
		return err
	}
	codes, err := pgx.CollectRows(res, pgx.RowTo[string])
	if err != nil {
		return err
	}
	if err := os.WriteFile(out, []byte(strings.Join(codes, "\n")+"\n"), 0o644); err != nil {
		return err
	}
	fmt.Printf("sample:     %d codes -> %s\n", len(codes), out)
	return nil
}
