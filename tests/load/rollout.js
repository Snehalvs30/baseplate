// Steady traffic through the ingress controller, counting every failed request.
// Run during a rollout: any request dropped while pods are replaced shows up here.
//   ./tests/load/rollout-test.sh <label>
import http from 'k6/http';
import { check } from 'k6';
import { Counter } from 'k6/metrics';

const BASE = __ENV.BASE || 'http://ledgerline.localhost';
const TOKEN = __ENV.TOKEN;
const failed = new Counter('failed_requests');

export const options = {
  scenarios: {
    steady: {
      // A fixed request rate, whatever the response times: a slow or failing
      // backend can't quietly reduce the load being measured.
      executor: 'constant-arrival-rate',
      rate: Number(__ENV.RATE || 20),
      timeUnit: '1s',
      duration: __ENV.DURATION || '4m',
      preAllocatedVUs: 20,
      maxVUs: 60,
    },
  },
  thresholds: {
    failed_requests: ['count==0'],   // the goal: not a single dropped request
  },
  summaryTrendStats: ['avg', 'p(50)', 'p(95)', 'p(99)', 'max'],
};

function params(name) {
  return {
    headers: { Authorization: `Bearer ${TOKEN}`, 'Content-Type': 'application/json' },
    timeout: '10s',
    tags: { name },
  };
}

export function setup() {
  if (!TOKEN) throw new Error('TOKEN is not set (use rollout-test.sh)');
  const res = http.post(`${BASE}/accounts`,
    JSON.stringify({ name: 'rollout-check', currency: 'USD' }), params('POST /accounts'));
  if (res.status !== 200 && res.status !== 201) {
    throw new Error(`could not create the test account: ${res.status} ${res.body}`);
  }
  return { accountId: res.json('id') };
}

export default function (data) {
  const res = http.get(`${BASE}/accounts/${data.accountId}`, params('GET /accounts/{id}'));
  const ok = check(res, { 'status is 200': (r) => r.status === 200 });
  if (!ok) failed.add(1, { status: String(res.status) });
}
