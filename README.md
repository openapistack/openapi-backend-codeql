# openapi-backend-codeql

CodeQL queries and models that find the ways [openapi-backend](https://github.com/openapistack/openapi-backend) gets wired up insecurely.

> **Status: draft.** Nothing is published yet. This README describes the packs we're building.

You declared `security:` in your OpenAPI definition. You registered a JWT security handler. Your tests pass. And every
unauthenticated request still reaches your operation handler, because nobody told openapi-backend to *reject* them.

That's not a bug in the library. It's the documented 5.x contract ([threat model §8](https://github.com/openapistack/openapi-backend/blob/main/docs/threat-model.md#8-what-does-the-library-not-do)):
security handlers and validation compute a verdict, and enforcing it is your job. It's also the most common security
report filed against the project. These queries find it, and its cousins, in your code before an attacker does.

## What's in the box

| Pack | What it does |
| --- | --- |
| `openapistack/openapi-backend-queries` | Queries for insecure openapi-backend configuration and usage. |
| `openapistack/openapi-backend-models` | A models-as-data extension that teaches CodeQL's built-in queries that `context.request` is user input. |

**Install the models pack even if you ignore the queries.** openapi-backend parses the request inside `node_modules`,
where CodeQL doesn't look, so taint gets lost on the way to your handlers. Without the models this is invisible to
CodeQL's standard SQL injection query:

```js
api.register('getPet', async (c) => {
  return db.query(`SELECT * FROM pets WHERE id = ${c.request.params.id}`); // 💥 SQL injection, silently missed
});
```

With the models pack, `c.request.params`, `.query`, `.headers`, `.cookies`, `.body` and `.requestBody` are remote
flow sources in every operation handler, security handler and lifecycle hook, however you registered them.
SQL injection, XSS, path traversal, SSRF, command injection: your existing CodeQL suite just starts working.

## Quick start

### GitHub code scanning

```yaml
# .github/workflows/codeql.yml
- uses: github/codeql-action/init@v3
  with:
    languages: javascript-typescript
    packs: |
      openapistack/openapi-backend-queries
      openapistack/openapi-backend-models
```

### CodeQL CLI

```sh
codeql pack download openapistack/openapi-backend-queries openapistack/openapi-backend-models
codeql database create db --language=javascript-typescript
codeql database analyze db openapistack/openapi-backend-queries \
  --model-packs=openapistack/openapi-backend-models \
  --format=sarif-latest --output=results.sarif
```

## The queries

Every query maps to a rule in the library's own [threat model](https://github.com/openapistack/openapi-backend/blob/main/docs/threat-model.md).
Each alert tells you which rule you broke and how to fix it.

| ID | Finds | Severity |
| --- | --- | --- |
| [`unenforced-security`](#unenforced-security) | Auth failures that still reach your handler | error |
| [`unenforced-validation`](#unenforced-validation) | Invalid requests that still reach your handler | warning |
| [`client-controlled-validation`](#client-controlled-validation) | A `validate` predicate the client can switch off | error |
| [`client-controlled-operation`](#client-controlled-operation) | Client input picking the operation or mock example | error |
| [`untrusted-definition`](#untrusted-definition) | The definition loaded from a client-influenced location | error |
| [`presence-only-security-handler`](#presence-only-security-handler) | Security handlers that check a credential exists, not that it's valid | warning |
| [`missing-security-handler`](#missing-security-handler) | A security scheme with no registered handler | warning |
| [`mock-in-production`](#mock-in-production) | Mock responses served from `notImplemented` with no environment guard | warning |
| [`unhandled-request-rejection`](#unhandled-request-rejection) | `handleRequest` promises nobody catches | note |

All IDs are prefixed with `js/openapi-backend/`.

---

### `unenforced-security`

**Security requirements are computed but never enforced.**

In non-strict mode, when a request fails its security requirements and no `unauthorizedHandler` is registered,
openapi-backend logs a warning and **calls your operation handler anyway**. The handler gets
`c.security.authorized === false` and nothing stops it.

❌ Vulnerable:

```js
const api = new OpenAPIBackend({
  definition: './openapi.yml', // every operation has `security: [{ jwt: [] }]`
  securityHandlers: {
    jwt: (c) => verifyJwt(c.request.headers.authorization),
  },
  handlers: {
    deleteUser: async (c) => users.delete(c.request.params.id), // anyone can call this
  },
});
```

✅ Fixed: pick one.

```js
// 1. Fail closed (recommended). handleRequest rejects with "401-unauthorized: ..."
const api = new OpenAPIBackend({ definition, strict: true, securityHandlers, handlers });

// 2. Register an unauthorizedHandler
api.register('unauthorizedHandler', (c, req, res) => res.status(401).json({ error: 'unauthorized' }));

// 3. Check it in every protected handler (easy to forget, which is why this query exists)
deleteUser: async (c) => {
  if (!c.security.authorized) throw new Unauthorized();
  return users.delete(c.request.params.id);
},
```

This query alerts only when **all** of these are true:

- the instance has security handlers or the definition declares `security`,
- `strict` is not `true`,
- no `unauthorizedHandler` is registered, whether in the constructor or via `register`, in any file,
- no `postSecurityHandler` throws or returns early on `!c.security.authorized`,
- the operation handler never reads `c.security.authorized`.

Threat model: [§9.1](https://github.com/openapistack/openapi-backend/blob/main/docs/threat-model.md#9-what-do-you-need-to-do), GHSA-7mmm-8m7g-cp5g.

---

### `unenforced-validation`

**Request validation is computed but never enforced.**

`validate: true` is the default, and it means *validation gets computed*, not *invalid requests get rejected*.
Without a `validationFail` handler (or `strict: true`), a body that fails your schema still reaches the handler.

❌ Vulnerable:

```js
// schema says: role is enum [user], maxLength 64 on name, additionalProperties: false
api.register('createUser', async (c) => {
  return users.insert(c.request.requestBody); // { role: 'admin', name: 'A'.repeat(1e6) } goes straight in
});
```

✅ Fixed:

```js
api.register('validationFail', (c, req, res) => res.status(400).json({ errors: c.validation.errors }));
// or: new OpenAPIBackend({ ..., strict: true })
```

No alert when the handler checks `c.validation.valid` or `c.validation.errors` itself.

Threat model: §9.2, §8 false friend 2.

---

### `client-controlled-validation`

**The client decides whether its own request gets validated.**

The `validate` option accepts a predicate. If its result depends on anything the client sends, any client can
skip validation.

❌ Vulnerable:

```js
const api = new OpenAPIBackend({
  definition: './openapi.yml',
  // "skip validation for internal traffic"
  validate: (c, req) => !req.headers['x-internal-request'], // curl -H 'x-internal-request: 1' ...
});
```

✅ Fixed: decide on something the client can't forge.

```js
validate: (c, req) => !isInternalNetwork(req.socket.remoteAddress),
// or: strip x-internal-request at the edge proxy, and document that you did
```

The query uses taint tracking from the request (`c.request.*` and raw framework requests passed as `handlerArgs`)
to the predicate's return value.

Threat model: §10.

---

### `client-controlled-operation`

**Client input picks the operation or example that gets used.**

`mockResponseForOperation` and `validateRequest(req, operationId)` trust their arguments. Plain property lookups on the
definition use them with no allow-list and no prototype-key guard.

❌ Vulnerable:

```js
app.get('/mock/:operationId', (req, res) => {
  const { status, mock } = api.mockResponseForOperation(req.params.operationId, {
    code: req.query.status,
    example: req.query.example, // pick any example from the definition, internal ones included
  });
  res.status(status).json(mock);
});

// validates against whichever operation the client names, e.g. one with a looser schema
const result = api.validator.validateRequest(req, req.headers['x-operation-id']);
```

✅ Fixed:

```js
// use the operation the router matched
notImplemented: (c) => c.api.mockResponseForOperation(c.operation.operationId),
```

Threat model: §9.10.

---

### `untrusted-definition`

**The OpenAPI definition comes from a location the client influences.**

The definition is code. External `$ref`s get resolved at `init` time, reading local files and fetching URLs. If a
client influences the path or URL, they can point it at a definition with no `security:` requirements, or use `$ref`
for SSRF and local file reads.

❌ Vulnerable:

```js
app.use('/tenants/:tenant', async (req, res) => {
  const api = new OpenAPIBackend({ definition: `./specs/${req.params.tenant}.yml` }); // ../../uploads/evil.yml
  await api.init();
  return api.handleRequest(req, req, res);
});
```

✅ Fixed:

```js
const apis = Object.fromEntries(
  await Promise.all(TENANTS.map(async (t) => [t, await new OpenAPIBackend({ definition: `./specs/${t}.yml` }).init()])),
);
app.use('/tenants/:tenant', (req, res) => apis[req.params.tenant]?.handleRequest(req, req, res) ?? res.sendStatus(404));
```

Threat model: §9.7.

---

### `presence-only-security-handler`

**The security handler only checks that a credential was sent, not that it's valid.**

A security handler's truthy return value *is* the auth decision. Returning the raw header means "any non-empty
string is a valid API key."

❌ Vulnerable:

```js
securityHandlers: {
  apiKey: (c) => c.request.headers['x-api-key'],           // 'x-api-key: lol' is authorized
  bearer: (c) => !!c.request.headers.authorization,         // so is 'Authorization: nope'
  session: (c) => c.request.cookies.session !== undefined,  // and any cookie at all
},
```

✅ Fixed:

```js
securityHandlers: {
  apiKey: async (c) => apiKeys.lookup(c.request.headers['x-api-key']), // returns the key owner, or null
  bearer: async (c) => jwt.verify(bearerToken(c), publicKey, { algorithms: ['RS256'] }),
},
```

The query alerts when the returned value comes from `c.request.headers` or `c.request.cookies` and passes only through
existence checks (`!!`, `!== undefined`, `Boolean()`, `.length`) with no call on the credential in between.

Threat model: §8 false friend 7.

---

### `missing-security-handler`

**A security scheme in the definition has no registered handler.**

An unregistered scheme counts as failed, so it fails closed. That's safe, but usually a sign that auth was never
wired up. Combined with [`unenforced-security`](#unenforced-security), it means the operation is wide open.

❌ Vulnerable:

```yaml
components:
  securitySchemes:
    jwt: { type: http, scheme: bearer }
    apiKey: { type: apiKey, in: header, name: x-api-key }
```

```js
api.registerSecurityHandler('jwt', verifyJwt); // apiKey never registered
```

This query reads the definition when it's a path to a YAML or JSON file in the repository, or an inline object.

Threat model: §9.3.

---

### `mock-in-production`

**Mock responses are served from `notImplemented` with no environment guard.**

`mockResponseForOperation` returns the definition's `example` values verbatim, including anything that looks like a
real credential or real customer data. In production, every unimplemented operation publishes them.

❌ Vulnerable:

```js
api.register('notImplemented', (c) => {
  const { status, mock } = c.api.mockResponseForOperation(c.operation.operationId);
  return { statusCode: status, body: JSON.stringify(mock) };
});
```

✅ Fixed:

```js
api.register('notImplemented', (c) => {
  if (process.env.NODE_ENV === 'production') return { statusCode: 501 };
  const { status, mock } = c.api.mockResponseForOperation(c.operation.operationId);
  return { statusCode: status, body: JSON.stringify(mock) };
});
```

Not reported in files under `test/`, `mock/` or `dev/`, or in files named `*.mock.*`.

Threat model: §9.8, §8 false friend 6.

---

### `unhandled-request-rejection`

**Nobody catches `handleRequest`.**

`handleRequest` rejects for unmatched routes with no `notFound` handler and for errors thrown by your handlers. With
`strict: true`, it also rejects for every 401 and 400. An uncaught rejection means a hung request, a 500 with a stack
trace, or on some setups a crashed process.

❌ Vulnerable:

```js
app.use((req, res) => api.handleRequest(req, req, res)); // Express 4 doesn't catch async errors
```

✅ Fixed:

```js
app.use((req, res, next) => api.handleRequest(req, req, res).catch(next));
```

Threat model: §9.4.

---

## Suppressing alerts

Some of these are judgment calls. When you've made one deliberately, dismiss the alert in code scanning with a reason
("public sandbox API, examples are meant to be public"), or exclude the query in your CodeQL config:

```yaml
query-filters:
  - exclude:
      id: js/openapi-backend/unhandled-request-rejection
```

## What these queries don't flag

The [threat model §10a](https://github.com/openapistack/openapi-backend/blob/main/docs/threat-model.md#10a-what-gets-reported-that-isnt-a-bug)
lists things scanners report that aren't bugs, like `RegExp` built from `apiRoot`, Ajv `strict: false`, and ReDoS in
your own schema `pattern`s. We don't flag those, and we don't flag operator choices like `quick: true` or custom
`ajvOpts`.

## openapi-backend 6.0

6.0 will reject unauthorized and invalid requests unconditionally. After you upgrade, `unenforced-security` and
`unenforced-validation` go quiet on their own. The other queries and the models pack still apply.

## Repository layout

```
queries/            openapistack/openapi-backend-queries
  src/<query>/      <Query>.ql, <Query>.qhelp, examples/{Bad,Good}.js
  lib/              shared modelling of OpenAPIBackend instances, handlers and context
models/             openapistack/openapi-backend-models (models-as-data YAML)
test/<query>/       CodeQL unit tests with .expected results
```

## Contributing

Found a false positive or a misuse we missed? Open an issue with a minimal snippet. Every new query needs a threat model
reference, a Bad/Good example pair and a test.

To report a security issue in openapi-backend itself, see its [SECURITY.md](https://github.com/openapistack/openapi-backend/blob/main/SECURITY.md).

## License

MIT
