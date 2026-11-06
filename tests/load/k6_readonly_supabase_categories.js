import http from 'k6/http';
import { check, sleep } from 'k6';

const TARGET_ENV = __ENV.TARGET_ENV;
const SUPABASE_URL = (__ENV.SUPABASE_URL || '').replace(/\/$/, '');
const SUPABASE_ANON_KEY = __ENV.SUPABASE_ANON_KEY;
const PEAK_VUS = Number(__ENV.K6_PEAK_VUS || '1000');
const PRODUCTION_PROJECT_REF = 'dzhhsoikzxibmngjzcch';

if (TARGET_ENV !== 'staging') {
  throw new Error('Safety stop: TARGET_ENV must be exactly "staging".');
}
if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
  throw new Error('Set SUPABASE_URL and SUPABASE_ANON_KEY for the staging project.');
}
if (SUPABASE_URL.includes(PRODUCTION_PROJECT_REF)) {
  throw new Error('Safety stop: the production project URL is not allowed.');
}
if (![1000, 10000].includes(PEAK_VUS)) {
  throw new Error('K6_PEAK_VUS must be 1000 or 10000.');
}

export const options = {
  stages: [
    { duration: '2m', target: 100 },
    { duration: '3m', target: 1000 },
    { duration: '5m', target: PEAK_VUS },
    { duration: '2m', target: 0 },
  ],
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<1000', 'p(99)<2000'],
  },
  discardResponseBodies: true,
};

const params = {
  headers: {
    apikey: SUPABASE_ANON_KEY,
    Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
    Accept: 'application/json',
  },
  tags: {
    test: 'readonly-categories',
    target: 'staging',
  },
};

export default function () {
  const response = http.get(
    `${SUPABASE_URL}/rest/v1/categories?select=id,name&is_active=eq.true&limit=30`,
    params,
  );

  check(response, {
    'categories endpoint returns HTTP 200': (r) => r.status === 200,
  });

  // Keep the test read-only and avoid an unrealistic tight-loop request storm.
  sleep(5);
}
