import http from 'k6/http';
import { check } from 'k6';
import { BASE_URL, scenario, summary } from './lib.js';

const codes = open('/results/sample_codes.txt').split('\n').map((s) => s.trim()).filter(Boolean);
if (codes.length === 0) {
  throw new Error('results/sample_codes.txt is empty: run `make seed` first');
}

const s = scenario('read');
export const options = s.options;

export function read() {
  const code = codes[Math.floor(Math.random() * codes.length)];
  const res = http.get(`${BASE_URL}/${code}`, { redirects: 0, tags: { name: 'GET /{code}' } });
  check(res, { 'status is 301/302': (r) => r.status === 301 || r.status === 302 });
}

export const handleSummary = summary('read', s.rate);
