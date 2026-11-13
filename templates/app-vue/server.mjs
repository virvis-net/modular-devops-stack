import { createReadStream, existsSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), 'dist');
const maxTelemetryBytes = 1024 * 1024;
const telemetryCollectorUrl = 'http://otel-collector.monitoring.svc:4318/v1/traces';
const buckets = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5];
const observations = new Map();

function normalizedMethod(method = '') {
  return ['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'].includes(method)
    ? method
    : 'OTHER';
}

function recordRequest(method, status, durationSeconds) {
  const key = `${normalizedMethod(method)}:${status}`;
  let observation = observations.get(key);
  if (!observation) {
    observation = { count: 0, duration: 0, buckets: buckets.map(() => 0) };
    observations.set(key, observation);
  }
  observation.count += 1;
  observation.duration += durationSeconds;
  buckets.forEach((boundary, index) => {
    if (durationSeconds <= boundary) observation.buckets[index] += 1;
  });
}

function renderMetrics() {
  const lines = [
    '# HELP http_server_requests_total Total HTTP server requests.',
    '# TYPE http_server_requests_total counter',
  ];
  const entries = [...observations.entries()].sort(([a], [b]) => a.localeCompare(b));

  for (const [key, observation] of entries) {
    const [method, status] = key.split(':');
    lines.push(`http_server_requests_total{method="${method}",status="${status}"} ${observation.count}`);
  }

  lines.push(
    '# HELP http_server_request_duration_seconds HTTP server request duration in seconds.',
    '# TYPE http_server_request_duration_seconds histogram',
  );
  for (const [key, observation] of entries) {
    const [method, status] = key.split(':');
    buckets.forEach((boundary, index) => {
      lines.push(`http_server_request_duration_seconds_bucket{method="${method}",status="${status}",le="${boundary}"} ${observation.buckets[index]}`);
    });
    lines.push(`http_server_request_duration_seconds_bucket{method="${method}",status="${status}",le="+Inf"} ${observation.count}`);
    lines.push(`http_server_request_duration_seconds_sum{method="${method}",status="${status}"} ${observation.duration}`);
    lines.push(`http_server_request_duration_seconds_count{method="${method}",status="${status}"} ${observation.count}`);
  }

  const memory = process.memoryUsage();
  lines.push(
    '# HELP process_resident_memory_bytes Resident memory size in bytes.',
    '# TYPE process_resident_memory_bytes gauge',
    `process_resident_memory_bytes ${memory.rss}`,
    '# HELP nodejs_heap_size_used_bytes Node.js heap used in bytes.',
    '# TYPE nodejs_heap_size_used_bytes gauge',
    `nodejs_heap_size_used_bytes ${memory.heapUsed}`,
    '# HELP nodejs_heap_size_total_bytes Node.js heap size in bytes.',
    '# TYPE nodejs_heap_size_total_bytes gauge',
    `nodejs_heap_size_total_bytes ${memory.heapTotal}`,
    '# HELP process_uptime_seconds Process uptime in seconds.',
    '# TYPE process_uptime_seconds gauge',
    `process_uptime_seconds ${process.uptime()}`,
  );
  return `${lines.join('\n')}\n`;
}

function sendText(response, status, body) {
  response.writeHead(status, {
    'Content-Type': 'text/plain; charset=utf-8',
    'X-Content-Type-Options': 'nosniff',
  });
  response.end(body);
}

async function readBoundedBody(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > maxTelemetryBytes) throw new RangeError('Telemetry request is too large');
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

async function forwardTelemetry(request, response) {
  if (request.method !== 'POST') {
    response.setHeader('Allow', 'POST');
    sendText(response, 405, 'method not allowed\n');
    return;
  }

  const origin = request.headers.origin;
  let originHost = '';
  try {
    originHost = new URL(origin).host.toLowerCase();
  } catch {
    sendText(response, 403, 'same-origin telemetry requests only\n');
    return;
  }
  if (originHost !== String(request.headers.host ?? '').toLowerCase()) {
    sendText(response, 403, 'same-origin telemetry requests only\n');
    return;
  }

  const contentType = String(request.headers['content-type'] ?? '').split(';')[0].trim();
  if (contentType !== 'application/x-protobuf') {
    sendText(response, 415, 'expected OTLP protobuf\n');
    return;
  }

  try {
    const body = await readBoundedBody(request);
    const collectorResponse = await fetch(telemetryCollectorUrl, {
      method: 'POST',
      headers: { 'content-type': 'application/x-protobuf' },
      body,
      signal: AbortSignal.timeout(5000),
    });
    const responseBody = Buffer.from(await collectorResponse.arrayBuffer());
    response.writeHead(collectorResponse.status, {
      'Content-Type': collectorResponse.headers.get('content-type') ?? 'application/json',
      'X-Content-Type-Options': 'nosniff',
    });
    response.end(responseBody);
  } catch (error) {
    const status = error instanceof RangeError ? 413 : 502;
    sendText(response, status, status === 413 ? 'telemetry request too large\n' : 'collector unavailable\n');
  }
}

function contentType(filePath) {
  const types = {
    '.css': 'text/css; charset=utf-8',
    '.html': 'text/html; charset=utf-8',
    '.ico': 'image/x-icon',
    '.js': 'text/javascript; charset=utf-8',
    '.json': 'application/json; charset=utf-8',
    '.png': 'image/png',
    '.svg': 'image/svg+xml',
    '.webp': 'image/webp',
    '.woff': 'font/woff',
    '.woff2': 'font/woff2',
  };
  return types[path.extname(filePath)] ?? 'application/octet-stream';
}

async function serveStatic(request, response, pathname) {
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    response.setHeader('Allow', 'GET, HEAD');
    sendText(response, 405, 'method not allowed\n');
    return;
  }

  let requestedPath;
  try {
    requestedPath = decodeURIComponent(pathname);
  } catch {
    sendText(response, 400, 'bad request\n');
    return;
  }

  const candidate = path.resolve(root, `.${requestedPath}`);
  if (candidate !== root && !candidate.startsWith(`${root}${path.sep}`)) {
    sendText(response, 404, 'not found\n');
    return;
  }

  let filePath = candidate;
  if (existsSync(filePath) && statSync(filePath).isDirectory()) {
    filePath = path.join(filePath, 'index.html');
  }
  if (!existsSync(filePath) || !statSync(filePath).isFile()) {
    filePath = path.join(root, 'index.html');
  }
  if (!existsSync(filePath)) {
    sendText(response, 503, 'frontend bundle unavailable\n');
    return;
  }

  response.writeHead(200, {
    'Content-Type': contentType(filePath),
    'Cache-Control': path.basename(filePath) === 'index.html' ? 'no-cache' : 'public, max-age=31536000, immutable',
    'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'strict-origin-when-cross-origin',
  });
  if (request.method === 'HEAD') {
    response.end();
    return;
  }
  createReadStream(filePath).pipe(response);
}

async function handleApplicationRequest(request, response) {
  let pathname;
  try {
    pathname = new URL(request.url ?? '/', 'http://frontend.local').pathname;
  } catch {
    sendText(response, 400, 'bad request\n');
    return;
  }

  if (pathname === '/healthz' || pathname === '/readyz') {
    sendText(response, 200, 'ok\n');
    return;
  }

  if (pathname === '/runtime-config.json') {
    let backendApiUrl = process.env.BACKEND_API_URL ?? 'http://staging.localhost:9080';
    try {
      const parsed = new URL(backendApiUrl);
      if (!['http:', 'https:'].includes(parsed.protocol) || parsed.username || parsed.password) {
        throw new Error('invalid backend URL');
      }
      backendApiUrl = parsed.origin;
    } catch {
      sendText(response, 500, 'invalid BACKEND_API_URL\n');
      return;
    }
    response.writeHead(200, {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
    });
    response.end(JSON.stringify({ backendApiUrl }));
    return;
  }

  if (pathname === '/_otel/v1/traces') {
    await forwardTelemetry(request, response);
    return;
  }

  await serveStatic(request, response, pathname);
}

const applicationServer = createServer((request, response) => {
  const startedAt = process.hrtime.bigint();
  const pathname = new URL(request.url ?? '/', 'http://frontend.local').pathname;
  response.once('finish', () => {
    if (['/healthz', '/readyz', '/metrics', '/_otel/v1/traces'].includes(pathname)) return;
    recordRequest(request.method, response.statusCode, Number(process.hrtime.bigint() - startedAt) / 1e9);
  });

  handleApplicationRequest(request, response).catch(() => {
    if (!response.headersSent) sendText(response, 500, 'internal server error\n');
    else response.destroy();
  });
});

const metricsServer = createServer((request, response) => {
  if (request.method !== 'GET' || request.url !== '/metrics') {
    sendText(response, 404, 'not found\n');
    return;
  }
  response.writeHead(200, { 'Content-Type': 'text/plain; version=0.0.4; charset=utf-8' });
  response.end(renderMetrics());
});

applicationServer.listen(Number(process.env.PORT ?? 8080), '0.0.0.0');
metricsServer.listen(Number(process.env.METRICS_PORT ?? 9090), '0.0.0.0');

function shutdown() {
  applicationServer.close();
  metricsServer.close();
}

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
