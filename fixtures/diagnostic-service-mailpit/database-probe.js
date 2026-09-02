import assert from "node:assert/strict";
import { copyFileSync, rmSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";

const databasePath = process.argv[2];
if (!databasePath) throw new TypeError("database path is required");

const snapshotPath = "/tmp/tn013-diagnostic-snapshot.db";
copyFileSync(databasePath, snapshotPath);
const database = new DatabaseSync(snapshotPath, { readOnly: true });
try {
  assert.deepEqual(
    database.prepare("SELECT version FROM schema_migrations ORDER BY version").all().map(({ version }) => version),
    [1, 2, 3, 4]
  );
  assert.equal(database.prepare("SELECT count(*) AS count FROM events").get().count, 2);
  assert.equal(database.prepare("SELECT count(*) AS count FROM canonical_results").get().count, 2);
  assert.equal(database.prepare("SELECT count(*) AS count FROM work_queue WHERE state='completed'").get().count, 2);
  assert.equal(database.prepare("SELECT count(*) AS count FROM notification_attempts WHERE status='sent'").get().count, 2);
  assert.equal(database.prepare("SELECT count(*) AS count FROM notification_attempts WHERE status!='sent'").get().count, 0);
  const incident = database.prepare("SELECT state, material_update_count, resolved_notification_count FROM incidents WHERE fingerprint='tn013-fingerprint'").get();
  assert.equal(incident.state, "resolved");
  assert.equal(incident.material_update_count, 0);
  assert.equal(incident.resolved_notification_count, 1);
} finally {
  database.close();
  rmSync(snapshotPath);
}

console.log("sqlite_snapshot=read_only migrations=1,2,3,4 events=2 canonical_results=2 attempts_sent=2 queue_completed=2");
