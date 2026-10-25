# 01 — the napkin estimate (stage 1)

Estimate first, measure second. The order matters: an estimate written down after the measurement
teaches you nothing. The method is chapter 2 of Alex Xu's *System Design Interview*
(back-of-the-envelope estimation); the system is the URL shortener from chapter 8.

## 1. Assumptions

Fill in your own numbers (defaults in parentheses):

| Parameter | Value |
|---|---|
| DAU — users per day | ____ |
| Actions per user per day | ____ |
| Read-to-write ratio | ____ (10:1) |
| Average record size | ____ (100 bytes: code + long URL + bookkeeping fields) |
| Retention | ____ (10 years) |

## 2. The arithmetic

Formulas:

- average RPS = DAU × actions / 86,400 (seconds per day; ≈ 10⁵ for a rough estimate);
- peak RPS = average × 2;
- writes per day = DAU × actions × write share;
- volume per year = writes per day × 365 × record size.

### Example A: DAU = 1 million, 1 click per day

- average RPS = 1,000,000 × 1 / 86,400 ≈ **12 RPS**;
- peak ≈ **23 RPS**;
- at 10:1, writes ≈ 1/11 of all actions → ~91,000 per day, ~1 write/s;
- volume per year ≈ 91,000 × 365 × 100 B ≈ **3.3 GB**.

Conclusion: a single database on a laptop handles this with a huge margin.

### Example B: Xu's numbers — 100 million new links per day

- writes/s = 100,000,000 / 86,400 ≈ **1,160 writes/s**;
- reads at 10:1 ≈ **11,600 reads/s**;
- records over 10 years = 100 M × 365 × 10 = 365 billion;
- volume over 10 years ≈ 365 billion × 100 B ≈ **36.5 TB**.

Conclusion: no longer one machine — sharding, a cache, a separate ID generator.

### Your estimate

```
average RPS    = ____ × ____ / 86,400 = ____
peak RPS       = ____
writes per day = ____
volume per year = ____
```

## 3. The bet — before measuring

Three values you write down **before** starting the load:

- `target_rps` — what read RPS the stand on your laptop should sustain (e.g. 500);
- `expected_p95_ms` — what p95 latency you expect at that RPS (e.g. 20);
- `expected_result` — one sentence: "will hold / won't hold, and why".

Something to think about: the table has 1 million rows and `GET /{code}` looks a row up by `code`.
How many rows will Postgres read per request? How many such requests can a pool of 10 connections
run at once?

Write it down:

```bash
make estimate RPS=500 P95=20 WHY="will hold: simple query, only a million rows"
```

The command creates `results/estimate.json`.

## 4. Run

```bash
make stage1
```

This is `up` → `seed` (if the table is empty) → `load/read.js` with RATE = target_rps for 60 seconds → `report`.

## 5. Result

`make report` prints a table:

```
target_rps   | actual RPS      | p95, ms    | p99, ms    | error rate
```

and a line "Estimate vs. fact: …". If p95 is above what you expected or errors exceed 1% —
"The estimate did not hold. Why — stages 2 and 3."

Not holding is the normal outcome of stage 1, not a broken stand. Write down here by how much
you were off and what your first hypothesis is:

```
off by ____× on p95
hypothesis: ____
```

`make check` verifies that the stage is complete.
