// TN-014 SQLite delivery probe — verifikasi firing dan resolved event tersimpan.
// Dijalankan read-only setelah Diagnostic Service berhenti.
import { copyFileSync, rmSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';

const [,, dbPath = '/data/diagnostic.db'] = process.argv;

const snapshotPath = '/tmp/tn014-probe-snapshot.db';
copyFileSync(dbPath, snapshotPath);

let db;
let eventCount, resolvedCount, firingCount;

try {
    db = new DatabaseSync(snapshotPath, { open: true, readOnly: true });

    eventCount = db.prepare('SELECT COUNT(*) AS n FROM events').get().n;
    resolvedCount = db.prepare(
        "SELECT COUNT(*) AS n FROM events WHERE status = 'resolved'"
    ).get().n;
    firingCount = db.prepare(
        "SELECT COUNT(*) AS n FROM events WHERE status = 'firing'"
    ).get().n;
} finally {
    if (db) db.close();
    rmSync(snapshotPath);
}

console.log(
    `sqlite_events=${eventCount}`,
    `sqlite_firing=${firingCount}`,
    `sqlite_resolved=${resolvedCount}`
);

if (eventCount < 1) {
    throw new Error('No events found in SQLite after delivery');
}
if (firingCount < 1) {
    throw new Error('No firing event found in SQLite');
}
if (resolvedCount < 1) {
    throw new Error('No resolved event found in SQLite');
}

console.log('sqlite_probe=passed');
