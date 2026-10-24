import http from 'k6/http';
import { check } from 'k6';
import { BASE_URL, scenario, summary } from './lib.js';

const s = scenario('write');
export const options = s.options;

export function write() {
  const body = JSON.stringify({ url: `https://example.com/k6/${__VU}/${__ITER}/${Date.now()}` });
  const res = http.post(`${BASE_URL}/shorten`, body, {
    headers: { 'Content-Type': 'application/json' },
    tags: { name: 'POST /shorten' },
  });
  check(res, { 'status is 201': (r) => r.status === 201 });
}

export const handleSummary = summary('write', s.rate);
