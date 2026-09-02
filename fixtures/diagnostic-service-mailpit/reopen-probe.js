import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { request } from "node:https";

const ca = readFileSync("/runtime/server.crt");

function ready() {
  return new Promise((resolve, reject) => {
    const call = request({
      hostname: "diagnostic-service",
      port: 8443,
      path: "/health/ready",
      ca,
      servername: "diagnostic-service",
      rejectUnauthorized: true
    }, (response) => {
      const chunks = [];
      response.on("data", (chunk) => chunks.push(chunk));
      response.on("end", () => resolve({ status: response.statusCode, body: Buffer.concat(chunks).toString("utf8") }));
    });
    call.on("error", reject);
    call.end();
  });
}

let response;
for (let attempt = 0; attempt < 60; attempt += 1) {
  try {
    response = await ready();
    if (response.status === 200) break;
  } catch {}
  await new Promise((resolve) => setTimeout(resolve, 250));
}

assert.equal(response?.status, 200);
assert.deepEqual(JSON.parse(response.body), { live: true, ready: true });
console.log("sqlite_application_reopen=passed readiness_after_reopen=passed");
