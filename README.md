<span id="npm--fix-hidden-readme-header"></span>

<h1 align="center">openapi-backend-codeql</h1>

[![CI](https://github.com/openapistack/openapi-backend-codeql/actions/workflows/ci.yml/badge.svg)](https://github.com/openapistack/openapi-backend-codeql/actions/workflows/ci.yml)
[![License](http://img.shields.io/:license-mit-blue.svg)](https://github.com/openapistack/openapi-backend-codeql/blob/main/LICENSE)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/openapistack/openapi-backend-codeql)
[![Buy me a coffee](https://img.shields.io/badge/donate-buy%20me%20a%20coffee-orange)](https://buymeacoff.ee/anttiviljami)

<p align="center"><b>Find insecure openapi-backend setups with CodeQL.</b></p>

<p align="center">CodeQL queries and models for <a href="https://github.com/openapistack/openapi-backend">openapi-backend</a>. Catch unenforced auth and validation before an attacker does.</p>

## Features

- [x] Flags APIs where failed auth or validation still reaches your operation handlers
- [x] Reads your OpenAPI definition to skip public operations and operations without input
- [x] Taint tracking for client-controlled `validate` predicates, operation lookups and definition paths
- [x] Makes CodeQL's built-in queries (SQL injection, XSS, path traversal, ...) see `context.request` as user input
- [x] Every query maps to a rule in the openapi-backend [threat model](https://github.com/openapistack/openapi-backend/blob/main/docs/threat-model.md)
- [x] Runnable [vulnerable and fixed examples](examples) for every query, verified in CI
- [x] Tuned for zero false positives on the [openapi-backend example projects](https://github.com/openapistack/openapi-backend/tree/examples)

## Quick Start

Add both packs to your GitHub code scanning workflow:

```yaml
- uses: github/codeql-action/init@v4
  with:
    languages: javascript-typescript
    packs: |
      openapistack/openapi-backend-queries
      openapistack/openapi-backend-models
```

Or run them with the [CodeQL CLI](https://docs.github.com/en/code-security/codeql-cli):

```
codeql database create db --language=javascript-typescript
codeql database analyze db openapistack/openapi-backend-queries \
  --download \
  --model-packs=openapistack/openapi-backend-models \
  --format=sarif-latest --output=results.sarif
```

## Queries

| ID | Finds | Severity |
| --- | --- | --- |
| [`js/openapi-backend/unenforced-security`](#unenforced-security) | Handlers that run when security requirements fail | error |
| [`js/openapi-backend/unenforced-validation`](#unenforced-validation) | Handlers that run when request validation fails | warning |
| [`js/openapi-backend/missing-security-handler`](#missing-security-handler) | Security schemes with no registered handler | warning |
| [`js/openapi-backend/client-controlled-validation`](#client-controlled-validation) | `validate` predicates the client can switch off | error |
| [`js/openapi-backend/client-controlled-operation`](#client-controlled-operation) | Client input choosing the operation or mock example | error |
| [`js/openapi-backend/untrusted-definition`](#untrusted-definition) | Definitions loaded from a client-influenced location | error |

### unenforced-security

Security handlers compute `c.security.authorized`, but they don't reject anything on their own. Without an
`unauthorizedHandler` or `strict: true`, openapi-backend still calls the operation handler for unauthorized requests.

```javascript
const api = new OpenAPIBackend({
  definition: './openapi.yml', // deleteUser requires a JWT
  securityHandlers: {
    jwt: (c) => verifyJwt(c.request.headers.authorization),
  },
  handlers: {
    deleteUser: (c) => users.delete(c.request.params.id), // ❌ runs for invalid tokens too
  },
});
```

Fix it with `strict: true`, an `unauthorizedHandler`, or a `c.security.authorized` check in every protected handler.

[See example](examples/unenforced-security)

### unenforced-validation

`validate: true` computes `c.validation`, but doesn't reject invalid requests on its own. Without a `validationFail`
handler or `strict: true`, requests that fail your schema still reach the operation handler.

```javascript
const api = new OpenAPIBackend({ definition: './openapi.yml' });

// schema: role is enum [user]
api.register('createUser', (c) => users.insert(c.request.requestBody)); // ❌ { role: 'admin' } gets in
```

Fix it with a `validationFail` handler or `strict: true`.

[See example](examples/unenforced-validation)

### missing-security-handler

A security scheme used in your definition has no registered handler. It fails closed, but usually means auth was
never wired up.

```javascript
// openapi.yml uses both jwt and apiKey
const api = new OpenAPIBackend({ definition: './openapi.yml' });
api.registerSecurityHandler('jwt', verifyJwt); // ❌ apiKey is never registered
```

[See example](examples/missing-security-handler)

### client-controlled-validation

A `validate` predicate that depends on request data lets any client skip validation.

```javascript
const api = new OpenAPIBackend({
  definition: './openapi.yml',
  validate: (c, req) => !req.headers['x-internal-request'], // ❌ curl -H 'x-internal-request: 1'
});
```

Decide on something the client can't forge, like `req.socket.remoteAddress`.

[See example](examples/client-controlled-validation)

### client-controlled-operation

`mockResponseForOperation()` and `validateRequest()` trust their arguments. Client input there picks which
operation, response or example gets used.

```javascript
app.get('/mock/:operationId', (req, res) => {
  const { status, mock } = api.mockResponseForOperation(req.params.operationId, {
    example: req.query.example, // ❌ any example in the definition, internal ones included
  });
  res.status(status).json(mock);
});
```

Use the operation the router matched: `c.operation.operationId`.

[See example](examples/client-controlled-operation)

### untrusted-definition

The definition decides which operations exist and which security requirements apply, and its external `$ref`s get
resolved from the filesystem and the network.

```javascript
app.use('/tenants/:tenant', async (req, res) => {
  const api = new OpenAPIBackend({ definition: `./specs/${req.params.tenant}.yml` }); // ❌ ../../uploads/evil
  await api.init();
  return api.handleRequest(req, req, res);
});
```

Load definitions from fixed paths at startup.

[See example](examples/untrusted-definition)

## Models

openapi-backend builds `context.request` inside `node_modules`, where CodeQL doesn't look. Without models, CodeQL's
built-in queries don't know that handler input comes from the client:

```javascript
api.register('getPet', (c) => {
  return db.query(`SELECT * FROM pets WHERE id = ${c.request.params.id}`); // ❌ missed without models
});
```

The `openapistack/openapi-backend-models` pack marks `c.request` as user input in every operation handler, security
handler, lifecycle handler and `validate` predicate, including TypeScript handlers typed `(c: Context) => ...`.
Your existing CodeQL setup then covers your openapi-backend handlers too.

[See example](examples/sql-injection)

## Avoiding false positives

The queries stay quiet when they can't be sure:

- If `definition` points to a YAML or JSON file in your repository, the queries read it. Public operations and
  operations without input are never flagged.
- If they can't read the definition, they alert once per `OpenAPIBackend` instance, and only if no handler checks
  the result.
- Handlers imported from another module, spread objects, wrapped handlers and `strict: process.env.STRICT` could all
  be doing the right thing, so they don't trigger alerts.
- Checks in helper functions, `postSecurityHandler` and `preOperationHandler` count.

CI runs the queries against the openapi-backend [example projects](https://github.com/openapistack/openapi-backend/tree/examples)
on every push and fails on any alert.

## Testing

Every example marks the lines that should be flagged with a `// $ Alert` comment:

```javascript
deleteUser: (c) => users.delete(c.request.params.id), // $ Alert
```

CI checks the examples with `codeql test run`, and again end to end: it builds a database from [`examples/`](examples),
analyzes it with both packs, and compares the SARIF output to the markers with
[`scripts/verify-sarif.mjs`](scripts/verify-sarif.mjs).

Run the tests locally with:

```
for pack in queries models tests examples; do codeql pack install $pack; done
codeql test run tests examples
```

## Commercial support

For assistance with securing openapi-backend in your company, reach out at support@openapistack.co.

## Contributing

openapi-backend-codeql is Free and Open Source Software. Issues and pull requests are more than welcome!

Found a false positive or a missed vulnerability? [Open an issue](https://github.com/openapistack/openapi-backend-codeql/issues/new/choose)
with a minimal snippet. New queries need a threat model reference, a `vulnerable.js` / `fixed.js` pair in
[`examples/`](examples) and edge case tests in [`tests/`](tests).

To release, bump `version` in `queries/qlpack.yml` and `models/qlpack.yml`, update the [CHANGELOG](CHANGELOG.md) and
publish a GitHub release tagged `v<version>`.
