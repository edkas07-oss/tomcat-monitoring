import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { request as httpRequest } from "node:http";
import { request as httpsRequest } from "node:https";

const ca = readFileSync("/runtime/server.crt");
const token = "tn013-disposable-bearer-token";
const diagnostic = { hostname: "diagnostic-service", port: 8443 };
const mailpit = { hostname: "mailpit", port: 8025 };

function request(requestFunction, options, body) {
  return new Promise((resolve, reject) => {
    const call = requestFunction(options, (response) => {
      const chunks = [];
      response.on("data", (chunk) => chunks.push(chunk));
      response.on("end", () => resolve({
        status: response.statusCode,
        body: Buffer.concat(chunks).toString("utf8")
      }));
    });
    call.on("error", reject);
    if (body !== undefined) call.end(JSON.stringify(body));
    else call.end();
  });
}

function diagnosticRequest(path, { method = "GET", authorization, body } = {}) {
  const headers = {};
  if (authorization) headers.authorization = authorization;
  if (body !== undefined) headers["content-type"] = "application/json";
  return request(httpsRequest, {
    ...diagnostic,
    path,
    method,
    headers,
    ca,
    servername: "diagnostic-service",
    rejectUnauthorized: true
  }, body);
}

function mailpitRequest(path) {
  return request(httpRequest, { ...mailpit, path, method: "GET" });
}

async function waitForReady() {
  for (let attempt = 0; attempt < 60; attempt += 1) {
    try {
      const response = await diagnosticRequest("/health/ready");
      if (response.status === 200) return response;
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error("Diagnostic Service was not ready within 15 seconds");
}

async function waitForMessages(expected) {
  for (let attempt = 0; attempt < 60; attempt += 1) {
    try {
      const response = await mailpitRequest("/api/v1/messages");
      if (response.status === 200) {
        const payload = JSON.parse(response.body);
        if (payload.total === expected) return payload;
      }
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error(`Mailpit did not capture ${expected} messages within 15 seconds`);
}

const alert = {
  status: "firing",
  labels: {
    alertname: "TomcatDown",
    severity: "critical",
    environment: "tn013",
    host: "tomcat-01",
    tomcat_instance: "default",
    job: "tomcat-jmx-exporter",
    instance: "tomcat-01:9404",
    service: "tomcat",
    check: "runtime-availability"
  },
  annotations: { summary: "Synthetic TN-013 disposable verification" },
  startsAt: "2026-09-02T01:00:00.000Z",
  endsAt: "0001-01-01T00:00:00.000Z",
  fingerprint: "tn013-fingerprint"
};
const webhook = (status) => ({
  version: "4",
  groupKey: '{}:{alertname="TomcatDown"}',
  status,
  receiver: "diagnostic-service",
  alerts: [{
    ...alert,
    status,
    endsAt: status === "resolved" ? "2026-09-02T01:05:00.000Z" : alert.endsAt
  }]
});

const ready = await waitForReady();
assert.deepEqual(JSON.parse(ready.body), { live: true, ready: true });
assert.equal((await diagnosticRequest("/health/live")).status, 200);
assert.equal((await diagnosticRequest("/metrics")).status, 200);

const endpoint = "/api/v1/alerts/alertmanager";
assert.equal((await diagnosticRequest(endpoint, {
  method: "POST", authorization: "Bearer rejected-token", body: webhook("firing")
})).status, 401);

const firing = await diagnosticRequest(endpoint, {
  method: "POST", authorization: `Bearer ${token}`, body: webhook("firing")
});
assert.equal(firing.status, 202);
assert.deepEqual(JSON.parse(firing.body), { accepted: 1, duplicate: 0 });
await waitForMessages(1);

const duplicate = await diagnosticRequest(endpoint, {
  method: "POST", authorization: `Bearer ${token}`, body: webhook("firing")
});
assert.equal(duplicate.status, 202);
assert.deepEqual(JSON.parse(duplicate.body), { accepted: 0, duplicate: 1 });

const resolved = await diagnosticRequest(endpoint, {
  method: "POST", authorization: `Bearer ${token}`, body: webhook("resolved")
});
assert.equal(resolved.status, 202);
assert.deepEqual(JSON.parse(resolved.body), { accepted: 1, duplicate: 0 });
const summary = await waitForMessages(2);

const expectedSubjects = new Set([
  "[firing] TomcatDown tn013/tomcat-01/default",
  "[resolved] TomcatDown tn013/tomcat-01/default"
]);
assert.equal(summary.messages.length, 2);
assert.deepEqual(new Set(summary.messages.map(({ Subject }) => Subject)), expectedSubjects);

for (const message of summary.messages) {
  assert.equal(message.From.Address, "diagnostic@tomcat-monitoring.invalid");
  assert.deepEqual(message.To.map(({ Address }) => Address), ["operator@tomcat-monitoring.invalid"]);
  const full = await mailpitRequest(`/api/v1/message/${message.ID}`);
  assert.equal(full.status, 200);
  const content = JSON.parse(full.body);
  for (const section of [
    "Alert Summary",
    "Diagnostic Assessment",
    "Key Metrics Snapshot",
    "Correlated Log Evidence",
    "Unavailable or Contradicting Evidence",
    "Recommended Operator Actions",
    "Rule and Diagnostic Traceability"
  ]) {
    assert.match(content.Text, new RegExp(section));
    assert.match(content.HTML, new RegExp(section));
  }
}

const metrics = await diagnosticRequest("/metrics");
assert.equal(metrics.status, 200);
assert.match(metrics.body, /notification_attempts_total\{status="sent"\} 2/);
assert.match(metrics.body, /notification_deliveries_total\{status="sent"\} 2/);

console.log("https_trust=passed live_ready_metrics=passed bearer_rejection=passed");
console.log("webhook_sequence=firing,duplicate,resolved mailpit_messages=2 text_html=passed");
