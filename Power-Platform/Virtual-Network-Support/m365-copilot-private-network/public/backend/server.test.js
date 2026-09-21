import { after, before, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createApp } from './server.js';

const fixtures = JSON.parse(readFileSync(new URL('./fixtures.json', import.meta.url), 'utf8'));
const observations = [];
const server = createApp({ logObservation: (observation) => observations.push(observation) });
let connectionCount = 0;
server.on('connection', () => { connectionCount++; });
let baseUrl;

before(async () => {
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});
after(async () => {
  await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
});

async function get(path, expectedStatus, options) {
  const beforeRequest = Date.now();
  const response = await fetch(`${baseUrl}${path}`, options);
  assert.equal(response.status, expectedStatus);
  assert.match(response.headers.get('cache-control'), /no-store/);
  assert.equal(response.headers.get('connection'), 'close');
  const text = await response.text();
  assert.ok(Buffer.byteLength(text) < 4000, 'Responses must remain small.');
  const body = JSON.parse(text);
  assert.equal(body.synthetic, true);
  assert.match(body.observationId, /^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/);
  assert.ok(Date.parse(body.observedAtUtc) >= beforeRequest);
  assert.ok(Date.parse(body.observedAtUtc) <= Date.now());
  assert.equal(typeof body.verificationCode, 'string');
  assert.ok(body.nonce === null || (typeof body.nonce === 'string' && body.nonce.length <= 100));
  return body;
}

test('health is live, uncached, and has a stored verification code', async () => {
  const first = await get('/health', 200);
  const second = await get('/health', 200);
  assert.equal(first.status, 'ok');
  assert.equal(first.verificationCode, fixtures.healthVerificationCode);
  assert.notEqual(first.observationId, second.observationId);
  assert.equal(first.nonce, null);
  assert.equal(server.maxRequestsPerSocket, 1);
});

test('consecutive observations establish separate backend TCP connections', async () => {
  const previousConnections = connectionCount;
  await get('/health?nonce=fresh-tcp-one', 200);
  await get('/health?nonce=fresh-tcp-two', 200);
  assert.equal(connectionCount - previousConnections, 2);
});

test('caller nonces are echoed and correlate exact backend-generated observations on every GET route', async () => {
  for (const [path, status] of [
    ['/health', 200],
    ['/mail/MAIL-1001', 200],
    ['/purchase-orders/PO-ZERO', 200],
    ['/purchase-orders/MISSING-9999', 404],
  ]) {
    const nonce = `probe-${path.replaceAll('/', '-')}`;
    const body = await get(`${path}?nonce=${encodeURIComponent(nonce)}`, status, {
      headers: { Authorization: 'Bearer never-log-this', 'Ocp-Apim-Subscription-Key': 'never-log-this-either' },
    });
    assert.equal(body.nonce, nonce);
    const observation = observations.find((entry) => entry.observationId === body.observationId);
    assert.deepEqual(observation, { nonce, path, observedAtUtc: body.observedAtUtc, observationId: body.observationId });
    assert.equal(JSON.stringify(observation).includes('never-log-this'), false);
    assert.equal(JSON.stringify(observation).includes(body.verificationCode), false);
  }
});

test('nonces are bounded, unique per request parameter, and never substitute for observation IDs', async () => {
  const nonce = 'x'.repeat(100);
  const first = await get(`/health?nonce=${nonce}`, 200);
  const second = await get(`/health?nonce=${nonce}`, 200);
  assert.equal(first.nonce, nonce);
  assert.equal(second.nonce, nonce);
  assert.notEqual(first.observationId, second.observationId);
  for (const query of ['nonce=', 'nonce=a&nonce=b', `nonce=${'x'.repeat(101)}`]) {
    const body = await get(`/health?${query}`, 400);
    assert.equal(body.error.code, 'InvalidNonce');
    assert.equal(body.nonce, null);
  }
});

test('logs exclude arbitrary query values, unrecognized paths, headers, and record contents', async () => {
  const body = await get('/health?token=never-log-this', 400);
  const observation = observations.find((entry) => entry.observationId === body.observationId);
  assert.deepEqual(Object.keys(observation).sort(), ['nonce', 'observationId', 'observedAtUtc', 'path']);
  assert.equal(JSON.stringify(observation).includes('never-log-this'), false);
  const unknown = await get('/never-log-this/arbitrary-secret', 404);
  assert.equal(observations.find((entry) => entry.observationId === unknown.observationId).path, '/unmatched');
  assert.equal((await get('/', 404)).error.code, 'RouteNotFound');
});

test('mail and SAP-shaped purchase orders preserve fixture values', async () => {
  for (const [route, collection] of [['mail', fixtures.mail], ['purchase-orders', fixtures.purchaseOrders]]) {
    for (const [id, fixture] of Object.entries(collection)) {
      const body = await get(`/${route}/${id}`, 200);
      const { verificationCode, ...record } = fixture;
      assert.deepEqual(body.record, record);
      assert.equal(body.verificationCode, verificationCode);
    }
  }
});

test('zero quantity and zero value are existing records, not missing records', async () => {
  const { record } = await get('/purchase-orders/PO-ZERO', 200);
  assert.equal(record.TotalNetAmount, 0);
  assert.equal(record.items[0].OrderQuantity, 0);
  assert.equal(record.items[0].NetAmount, 0);
});

test('unknown IDs return real 404s with fresh metadata', async () => {
  for (const route of ['mail', 'purchase-orders']) {
    const body = await get(`/${route}/MISSING-9999`, 404);
    assert.equal(body.error.code, 'RecordNotFound');
    assert.equal(body.error.id, 'MISSING-9999');
    assert.equal(body.verificationCode, fixtures.errorVerificationCode);
    assert.equal(body.record, undefined);
  }
});

test('missing IDs, malformed IDs, query strings, and unknown routes fail explicitly', async () => {
  for (const route of ['/mail', '/mail/', '/purchase-orders', '/purchase-orders/']) {
    assert.equal((await get(route, 400)).error.code, 'MissingId');
  }
  for (const route of ['/mail/%ZZ', '/mail/a%2Fb', `/mail/${'x'.repeat(65)}`]) {
    assert.equal((await get(route, 400)).error.code, 'InvalidId');
  }
  assert.equal((await get('/health?cached=true', 400)).error.code, 'UnsupportedQuery');
  assert.equal((await get('/unknown', 404)).error.code, 'RouteNotFound');
  assert.equal((await get('/mail/constructor', 404)).error.code, 'RecordNotFound');
});

test('write methods cannot mutate fixtures', async () => {
  for (const method of ['POST', 'PUT', 'PATCH', 'DELETE']) {
    assert.equal((await get('/purchase-orders/PO-ZERO', 405, { method })).error.code, 'MethodNotAllowed');
  }
  assert.equal((await get('/purchase-orders/PO-ZERO', 200)).record.TotalNetAmount, 0);
});

test('OpenAPI keeps stable read-only action IDs and never includes stored verification values', () => {
  const source = readFileSync(new URL('../infra/backend.openapi.json', import.meta.url), 'utf8');
  const api = JSON.parse(source);
  assert.deepEqual(Object.values(api.paths).map((path) => path.get.operationId).sort(),
    ['getHealth', 'getMail', 'getPurchaseOrder']);
  for (const path of Object.values(api.paths)) {
    assert.deepEqual(Object.keys(path), ['get']);
    const nonce = path.get.parameters.find((parameter) => parameter.name === 'nonce');
    assert.equal(nonce.in, 'query');
    assert.equal(nonce.required, false);
    assert.equal(nonce.schema.maxLength, 100);
  }
  const codes = [
    fixtures.healthVerificationCode,
    fixtures.errorVerificationCode,
    ...Object.values(fixtures.mail).map((record) => record.verificationCode),
    ...Object.values(fixtures.purchaseOrders).map((record) => record.verificationCode),
  ];
  for (const code of codes) assert.equal(source.includes(code), false);
});
