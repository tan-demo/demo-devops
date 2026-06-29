import http from "k6/http";
import { check, sleep } from "k6";

const BASE = __ENV.BASE_URL || "http://k3d-dev-serverlb";

export const options = {
  stages: [
    { duration: "30s", target: 10 },
    { duration: "1m", target: 30 },
    { duration: "1m", target: 30 },
    { duration: "30s", target: 0 },
  ],
  thresholds: {
    // Justified from the measured baseline in LOADTEST.md
    http_req_failed: ["rate<0.01"],
    http_req_duration: ["p(95)<400"],
  },
};

export default function () {
  const res = http.get(`${BASE}/api/quote`);
  check(res, { "status is 200": (r) => r.status === 200 });
  sleep(0.5);
}
