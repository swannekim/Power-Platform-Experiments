import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const fixtures = JSON.parse(readFileSync(new URL('./fixtures.json', import.meta.url), 'utf8'));

function sendResponse(response, status, payload, context, logObservation, verificationCode = fixtures.errorVerificationCode) {
  const observation = {
    nonce: context.nonce,
    path: context.path,
    observedAtUtc: new Date().toISOString(),
    observationId: randomUUID(),
  };
  const body = JSON.stringify({
    synthetic: true,
    ...payload,
    nonce: observation.nonce,
    observedAtUtc: observation.observedAtUtc,
    observationId: observation.observationId,
    verificationCode,
  });
  response.shouldKeepAlive = false;
  response.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': 'no-store, max-age=0',
    Pragma: 'no-cache',
    'X-Content-Type-Options': 'nosniff',
    Connection: 'close',
    ...(status === 405 ? { Allow: 'GET' } : {}),
  });
  response.end(body);
  logObservation(observation);
}

export function createApp({ logObservation = (observation) => console.log(JSON.stringify(observation)) } = {}) {
  const server = createServer({ maxHeaderSize: 8192, requestTimeout: 15000, headersTimeout: 10000 }, (request, response) => {
    const context = { nonce: null, path: '/unmatched' };
    const send = (status, payload, verificationCode) =>
      sendResponse(response, status, payload, context, logObservation, verificationCode);
    if (request.method !== 'GET') {
      send(405, { error: { code: 'MethodNotAllowed', message: 'Only GET is supported.' } });
      return;
    }

    let url;
    try {
      url = new URL(request.url, 'http://localhost');
    } catch (error) {
      if (!(error instanceof TypeError)) throw error;
      send(400, { error: { code: 'InvalidUrl', message: 'Invalid request URL.' } });
      return;
    }

    // Only log bounded supported paths, never arbitrary URLs, query strings, headers, or credentials.
    if (/^\/(?:health|(?:mail|purchase-orders)(?:\/[A-Za-z0-9-]{1,64})?)$/.test(url.pathname)) {
      context.path = url.pathname;
    }
    const nonces = url.searchParams.getAll('nonce');
    if (nonces.length > 1 || (nonces.length === 1 && (nonces[0].length < 1 || nonces[0].length > 100))) {
      send(400, { error: { code: 'InvalidNonce', message: 'Provide at most one nonce, containing 1-100 characters.' } });
      return;
    }
    context.nonce = nonces[0] ?? null;
    if ([...url.searchParams.keys()].some((key) => key !== 'nonce')) {
      send(400, { error: { code: 'UnsupportedQuery', message: 'Only the optional nonce query parameter is supported.' } });
      return;
    }
    if (url.pathname === '/health') {
      send(200, { status: 'ok', service: 'synthetic-private-gateway' }, fixtures.healthVerificationCode);
      return;
    }
    if (/^\/(mail|purchase-orders)\/?$/.test(url.pathname)) {
      send(400, { error: { code: 'MissingId', message: 'A record ID is required.' } });
      return;
    }

    const match = /^\/(mail|purchase-orders)\/([^/]+)$/.exec(url.pathname);
    if (!match) {
      send(404, { error: { code: 'RouteNotFound', message: 'No such read-only API route.' } });
      return;
    }

    let id;
    try {
      id = decodeURIComponent(match[2]);
    } catch (error) {
      if (!(error instanceof URIError)) throw error;
      send(400, { error: { code: 'InvalidId', message: 'The record ID is malformed.' } });
      return;
    }
    if (!/^[A-Za-z0-9-]{1,64}$/.test(id)) {
      send(400, { error: { code: 'InvalidId', message: 'Use 1-64 letters, digits, or hyphens.' } });
      return;
    }

    const collection = match[1] === 'mail' ? fixtures.mail : fixtures.purchaseOrders;
    if (!Object.hasOwn(collection, id)) {
      send(404, { error: { code: 'RecordNotFound', message: 'The synthetic record does not exist.', id } });
      return;
    }
    const { verificationCode, ...record } = collection[id];
    send(200, { record }, verificationCode);
  });
  server.maxRequestsPerSocket = 1;
  return server;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const port = Number(process.env.PORT ?? 8080);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error('PORT must be an integer between 1 and 65535.');
  }
  createApp().listen(port, '0.0.0.0', () => {
    console.log(`Synthetic read-only API listening on port ${port}.`);
  });
}
