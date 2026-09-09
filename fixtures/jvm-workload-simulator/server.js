const https = require('https');
const fs = require('fs');

const certPath = process.env.TLS_CERT_PATH || '/run/secrets/tomcat-jmx-exporter/server.crt';
const keyPath = process.env.TLS_KEY_PATH || '/run/secrets/tomcat-jmx-exporter/server.key';

const options = {
  key: fs.readFileSync(keyPath),
  cert: fs.readFileSync(certPath)
};

let activeProfile = 'baseline'; // baseline, gc-pause, gc-overhead, memory-pressure, thread-saturated, all-firing
let gcSecondsSum = 0.05;
let lastTimestamp = Date.now();

const server = https.createServer(options, (req, res) => {
  const url = new URL(req.url, `https://${req.headers.host || 'localhost'}`);
  
  if (url.pathname === '/metrics') {
    const now = Date.now();
    const elapsedSec = (now - lastTimestamp) / 1000.0;
    lastTimestamp = now;

    let pauseMax = 0.025;
    let oldGenUsed = 14017096; // ~14MB
    const oldGenMax = 8396996608; // ~8.39GB
    let busyThreads = 0;
    const currentThreads = 10;

    const isAllFiring = activeProfile === 'all-firing';
    const isGCPause = isAllFiring || activeProfile === 'gc-pause';
    const isGCOverhead = isAllFiring || activeProfile === 'gc-overhead';
    const isMemoryPressure = isAllFiring || activeProfile === 'memory-pressure';
    const isThreadSaturated = isAllFiring || activeProfile === 'thread-saturated';

    if (isGCPause) {
      pauseMax = 2.45; // Exceeds 1.5s threshold
    }

    if (isGCOverhead) {
      // 25% of elapsed time spent in GC (exceeds 15% threshold)
      gcSecondsSum += elapsedSec * 0.25;
    } else {
      gcSecondsSum += elapsedSec * 0.002;
    }

    if (isMemoryPressure) {
      oldGenUsed = 8000000000; // 95.27% of max (exceeds 90% threshold)
    }

    if (isThreadSaturated) {
      busyThreads = 10; // 100% saturation (exceeds 1.0 threshold)
    }

    const metricsBody = `# HELP jmx_scrape_duration_seconds Time this JMX scrape took, in seconds.
# TYPE jmx_scrape_duration_seconds gauge
jmx_scrape_duration_seconds 0.015
# HELP jmx_scrape_error Non-zero if this scrape failed.
# TYPE jmx_scrape_error gauge
jmx_scrape_error 0.0
# HELP jvm_gc_pause_seconds_max Maximum GC pause duration in seconds
# TYPE jvm_gc_pause_seconds_max gauge
jvm_gc_pause_seconds_max ${pauseMax.toFixed(3)}
# HELP jvm_gc_collection_seconds_count Number of GC collections
# TYPE jvm_gc_collection_seconds_count counter
jvm_gc_collection_seconds_count{gc="G1 Young Generation"} 120
jvm_gc_collection_seconds_count{gc="G1 Old Generation"} 2
# HELP jvm_gc_collection_seconds_sum Total time spent in GC in seconds
# TYPE jvm_gc_collection_seconds_sum counter
jvm_gc_collection_seconds_sum{gc="G1 Young Generation"} ${gcSecondsSum.toFixed(4)}
jvm_gc_collection_seconds_sum{gc="G1 Old Generation"} 0.0500
# HELP jvm_memory_pool_used_bytes Used memory in bytes per pool
# TYPE jvm_memory_pool_used_bytes gauge
jvm_memory_pool_used_bytes{pool="G1 Eden Space"} 16777216
jvm_memory_pool_used_bytes{pool="G1 Survivor Space"} 386816
jvm_memory_pool_used_bytes{pool="G1 Old Gen"} ${oldGenUsed}
jvm_memory_pool_used_bytes{pool="Metaspace"} 25675936
# HELP jvm_memory_pool_max_bytes Maximum memory in bytes per pool
# TYPE jvm_memory_pool_max_bytes gauge
jvm_memory_pool_max_bytes{pool="G1 Eden Space"} -1
jvm_memory_pool_max_bytes{pool="G1 Survivor Space"} -1
jvm_memory_pool_max_bytes{pool="G1 Old Gen"} ${oldGenMax}
jvm_memory_pool_max_bytes{pool="Metaspace"} -1
# HELP tomcat_threads_busy_threads Number of busy request handler threads
# TYPE tomcat_threads_busy_threads gauge
tomcat_threads_busy_threads{name="http-nio-8080"} ${busyThreads}
# HELP tomcat_threads_current_threads Total number of request handler threads
# TYPE tomcat_threads_current_threads gauge
tomcat_threads_current_threads{name="http-nio-8080"} ${currentThreads}
`;

    res.writeHead(200, {
      'Content-Type': 'text/plain; version=0.0.4; charset=utf-8'
    });
    res.end(metricsBody);
  } else if (url.pathname === '/set-profile') {
    const profile = url.searchParams.get('profile') || 'baseline';
    activeProfile = profile;
    lastTimestamp = Date.now();
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', activeProfile: activeProfile, timestamp: Date.now() }));
  } else if (url.pathname === '/status') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', activeProfile: activeProfile, gcSecondsSum: gcSecondsSum }));
  } else {
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Not Found');
  }
});

const PORT = parseInt(process.env.PORT || '9404', 10);
server.listen(PORT, '0.0.0.0', () => {
  console.log(`JVM Workload Simulator listening on HTTPS port ${PORT} with profile ${activeProfile}`);
});

const http = require('http');
const HTTP_PORT = parseInt(process.env.HTTP_PORT || '8080', 10);
const httpServer = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'UP' }));
  } else {
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Not Found');
  }
});
httpServer.listen(HTTP_PORT, '0.0.0.0', () => {
  console.log(`HTTP Health endpoint listening on port ${HTTP_PORT}`);
});
