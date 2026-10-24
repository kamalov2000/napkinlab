// Shared helpers for k6 scenarios.

export const BASE_URL = __ENV.BASE_URL || 'http://api:8080';

export function scenario(exec) {
  const rate = parseInt(__ENV.RATE || '100', 10);
  return {
    rate,
    options: {
      scenarios: {
        main: {
          executor: 'constant-arrival-rate',
          exec,
          rate,
          timeUnit: '1s',
          duration: __ENV.DURATION || '60s',
          preAllocatedVUs: parseInt(__ENV.PRE_ALLOCATED_VUS || '50', 10),
          maxVUs: parseInt(__ENV.MAX_VUS || '500', 10),
        },
      },
      thresholds: {
        http_req_failed: ['rate<0.01'],
      },
      summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
    },
  };
}

function metric(data, name, key) {
  const m = data.metrics[name];
  return m && m.values[key] !== undefined ? m.values[key] : 0;
}

function round(x) {
  return Math.round(x * 100) / 100;
}

// Flat numbers with unique keys, so scripts/report.sh can read them without jq.
function flat(data, kind, rate) {
  return {
    napkin_kind: kind,
    napkin_target_rps: rate,
    napkin_actual_rps: round(metric(data, 'http_reqs', 'rate')),
    napkin_requests: metric(data, 'http_reqs', 'count'),
    napkin_p95_ms: round(metric(data, 'http_req_duration', 'p(95)')),
    napkin_p99_ms: round(metric(data, 'http_req_duration', 'p(99)')),
    napkin_med_ms: round(metric(data, 'http_req_duration', 'med')),
    napkin_error_rate: round(metric(data, 'http_req_failed', 'rate') * 10000) / 10000,
    napkin_dropped_iterations: metric(data, 'dropped_iterations', 'count'),
    napkin_max_vus: metric(data, 'vus_max', 'max'),
  };
}

export function summary(kind, rate) {
  return (data) => {
    const f = flat(data, kind, rate);
    const ts = new Date().toISOString().replace(/[-:]/g, '').replace(/\..+/, '');
    const file = `/results/${kind}_${rate}rps_${ts}.json`;
    const text = [
      '',
      `${kind}: target ${rate} rps, ${f.napkin_requests} requests`,
      `  actual rps        ${f.napkin_actual_rps}`,
      `  median / p95 / p99 ${f.napkin_med_ms} / ${f.napkin_p95_ms} / ${f.napkin_p99_ms} ms`,
      `  errors            ${(f.napkin_error_rate * 100).toFixed(2)}%`,
      `  dropped iters     ${f.napkin_dropped_iterations} (k6 ran out of VUs, max ${f.napkin_max_vus})`,
      `  saved             ${file}`,
      '',
    ].join('\n');
    return {
      stdout: text,
      [file]: JSON.stringify({ napkin: f, k6: data }, null, 2),
    };
  };
}
