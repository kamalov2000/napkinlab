# 00 — starting the stand

## What you need
- Docker Desktop (Windows: with the WSL2 backend) or Docker on Linux/macOS.
- `make` and `bash` (present in WSL, Linux, macOS or Git Bash).
- ~4 GB of free memory, ~1 GB of disk.

## Steps
```bash
make up                      # postgres, redis, api — wait for healthy
make seed N=1000000          # a million links, 1–2 minutes
curl -X POST localhost:8080/shorten -d '{"url":"https://example.com"}'
curl -I localhost:8080/<code from the response>
```

## What you should see
`make up` ends with a table of three containers, all with `(healthy)` in STATUS:

```
NAME                   SERVICE    STATUS
napkinlab-api-1        api        Up ... (healthy)
napkinlab-postgres-1   postgres   Up ... (healthy)
napkinlab-redis-1      redis      Up ... (healthy)
```

`make seed` prints progress every 100,000 rows; at the end — the row count, the table size,
and it writes 20 random codes to `results/sample_codes.txt`.

`curl -I` returns `HTTP/1.1 302 Found` with a `Location` header carrying the original URL.

Service counters: `curl localhost:8080/metrics`.

## If something is off
- `make logs` — logs of all containers.
- Port 8080 is taken — change `API_PORT` in `.env`.
- Start from scratch — `make clean`, then `make up` again.

Next — [01-estimate.md](01-estimate.md).
