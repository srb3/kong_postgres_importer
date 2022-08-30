import http from 'k6/http';
import { randomIntBetween } from 'https://jslib.k6.io/k6-utils/1.1.0/index.js';
import { SharedArray } from 'k6/data';

// not using SharedArray here will mean that the code in the function call (that is what loads and
// parses the json) will be executed per each VU which also means that there will be a complete copy
// per each VU

const data = new SharedArray('data_file', function () {
  console.log("WILL OPEN: "+__ENV.DATA_FILE)
  return JSON.parse(open(__ENV.DATA_FILE));
});

export const options = {
  thresholds: {
    http_req_failed: ['rate<0.01'], // http errors should be less than 1%
    http_req_duration: ['p(95)<300'], // 95% of requests should be below 2ms
  },
  scenarios: {
    constant_request_rate: {
      executor: 'constant-arrival-rate',
      rate: __ENV.RATE || 1,
      timeUnit: __ENV.TIME_UNIT || '5s',
      duration: __ENV.DURATION || '15m',
      preAllocatedVUs: __ENV.VUS || 50,
      maxVUs: __ENV.MAX_VUS || 900,
    },
  },
};

export default function () {
  let proxy_url = __ENV.PROXY_URL || 'http://localhost:8000'
  let paths = data
  let total = (paths.length - 1)
  let path = paths[randomIntBetween(0, total)];
  let endpoint = proxy_url + '/' + path
  let res = http.get(endpoint);
}
