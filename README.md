# openapi-backend-codeql

[![CI](https://github.com/openapistack/openapi-backend-codeql/actions/workflows/ci.yml/badge.svg)](https://github.com/openapistack/openapi-backend-codeql/actions/workflows/ci.yml)

CodeQL queries and models that find the ways [openapi-backend](https://github.com/openapistack/openapi-backend) gets wired up insecurely.

You declared `security:` in your OpenAPI definition. You registered a JWT security handler. Your tests pass. And every
unauthenticated request still reaches your operation handler, because nobody told openapi-backend to *reject* them.

That's not a bug in the library. It's the documented 5.x contract ([threat model §8](https://github.com/openapistack/openapi-backend/blob/main/docs/threat-model.md#8-what-does-the-library-not-do)):
security handlers and validation compute a verdict, and enforcing it is your job. It's also the most common security
report filed against the project. These queries find it, and its cousins, before an attacker does.

## What's in the box

| Pack | What it does |
| --- | --- |
| [`openapistack/openapi-backend-queries`](queries) | Six queries for insecure openapi-backend configuration and usage. |
| [`openapistack/openapi-backend-models`](models) | Models that teach CodeQL's built-in queries that `context.request` is user input. |

**Install the models pack even if you ignore the queries.** openapi-backend parses the request inside `node_modules`,
where CodeQL doesn't look, so taint gets lost on the way to your handlers. Without the models this is invisible to
CodeQL's standard SQL injection query:

```js
api.register('getPet', (c) => {
  return db.query(`SELECT * FROM pets WHERE id = ${c.request.params.id}`); // 💥 SQL injection, silently missed
});
```

With the models pack, `c.request` is a remote flow source in every operation handler, security handler, lifecycle
hook and `validate` predicate. That covers handlers passed in the constructor, via `register()` or
`registerSecurityHandler()`, on the awaited result of `init()`, and TypeScript functions typed `(c: Context) => ...`.
SQL injection, XSS, path traversal, SSRF and command injection: your existing CodeQL setup just starts working.
CI proves this on every run ([`examples/sql-injection`](examples/sql-injection)).

## Quick start

> **Not published yet.** Until the packs are on the GitHub Container Registry, clone this repository and run the
> CLI commands under [Development](#development) with `--additional-packs=path/to/openapi-backend-codeql`.

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

Every query maps to a rule in the library's own [threat model](https://github.com/openapistack/openapi-backend/blob/main/docs/threat-model.md),
and every one has a runnable [`vulnerable.js` and `fixed.js`](examples) that CI checks.

| ID | Finds | Severity |
| --- | --- | --- |
| [`unenforced-security`](#unenforced-security) | Auth failures that still reach your handler | error |
| [`unenforced-validation`](#unenforced-validation) | Invalid requests that still reach your handler | warning |
| [`missing-security-handler`](#missing-security-handler) | A security scheme with no registered handler | warning |
| [`client-controlled-validation`](#client-controlled-validation) | A `validate` predicate the client can switch off | error |
| [`client-controlled-operation`](#client-controlled-operation) | Client input picking the operation, response or mock example | error |
| [`untrusted-definition`](#untrusted-definition) | The definition loaded from a client-influenced location | error |

All IDs are prefixed with `js/openapi-backend/`.

### Built to stay quiet

A query that cries wolf gets disabled, so every query here errs on the side of silence:

- **When the definition is in your repo, the queries read it.** Pass `definition` as a constant path, or
  `path.join(__dirname, ...)`, to a YAML or JSON file, and the queries use it. Public operations (`security: []`,
  or an anonymous `{}` requirement) and operations with no input are never flagged.
- **When the definition isn't in your repo, they alert once per instance, not per handler.** And only when no
  handler at all checks the result.
- **When they can't see your code, they stay quiet.** A `handlers` object that's imported or uses `...spread`,
  handlers wrapped in a helper, `register()` with a computed name, or `strict: process.env.STRICT`: any of these
  could be doing the right thing, so there's no alert.
- **Checks you delegate still count.** A check of `c.security.authorized` or `c.validation` in a helper the handler
  calls, in a `postSecurityHandler`, or in a `preOperationHandler` counts as enforcement.

We run the queries against the 14 integration examples on openapi-backend's
[`examples` branch](https://github.com/openapistack/openapi-backend/tree/examples). Zero alerts as shipped. Remove
their `unauthorizedHandler`, and exactly the secured operations get flagged.

---

### `unenforced-security`

**Security requirements are computed but never enforced.**

In non-strict mode, when a request fails its security requirements and no `unauthorizedHandler` is registered,
openapi-backend logs a warning and **calls your operation handler anyway** with `c.security.authorized === false`.

❌ [Vulnerable](examples/unenforced-security/vulnerable.js)

```js
const api = new OpenAPIBackend({
  definition: './openapi.yml', // deleteUser requires a JWT
  securityHandlers: {
    jwt: (c) => verifyJwt(c.request.headers.authorization),
  },
  handlers: {
    deleteUser: (c) => users.delete(c.request.params.id), // anyone can call this
  },
});
```

✅ [Fixed](examples/unenforced-security/fixed.js): pick one.

```js
// 1. Fail closed (recommended). handleRequest rejects with "401-unauthorized: ..."
new OpenAPIBackend({ definition, strict: true, securityHandlers, handlers });

// 2. Register an unauthorizedHandler
api.register('unauthorizedHandler', (c, req, res) => res.status(401).json({ error: 'unauthorized' }));

// 3. Check it in every protected handler (easy to forget, which is why this query exists)
deleteUser: (c) => {
  if (!c.security.authorized) throw new Unauthorized();
  return users.delete(c.request.params.id);
},
```

Threat model [§9.1](https://github.com/openapistack/openapi-backend/blob/main/docs/threat-model.md#9-what-do-you-need-to-do), GHSA-7mmm-8m7g-cp5g.

---

### `unenforced-validation`

**Request validation is computed but never enforced.**

`validate: true` is the default, and it means *validation gets computed*, not *invalid requests get rejected*.
Without a `validationFail` handler (or `strict: true`), a body that fails your schema still reaches the handler.

❌ [Vulnerable](examples/unenforced-validation/vulnerable.js)

```js
// schema: role is enum [user], name has maxLength 64, additionalProperties: false
api.register('createUser', (c) => users.insert(c.request.requestBody)); // { role: 'admin', ... } goes straight in
```

✅ [Fixed](examples/unenforced-validation/fixed.js)

```js
api.register('validationFail', (c, req, res) => res.status(400).json({ errors: c.validation.errors }));
// or: new OpenAPIBackend({ ..., strict: true })
```

Only handlers that read `c.request` are flagged. A handler that only returns static data doesn't care.

Threat model §9.2, §8 false friend 2.

---

### `missing-security-handler`

**A security scheme used in the definition has no registered handler.**

An unregistered scheme counts as failed, so it fails closed. That's safe on its own, but it's a sign that auth was
never wired up. Combined with [`unenforced-security`](#unenforced-security), the operation is wide open.

❌ [Vulnerable](examples/missing-security-handler/vulnerable.js)

```yaml
security:
  - jwt: []
paths:
  /reports/export:
    post:
      security:
        - apiKey: []
```

```js
api.registerSecurityHandler('jwt', verifyJwt); // apiKey never registered
```

✅ [Fixed](examples/missing-security-handler/fixed.js): register a handler for every scheme you use. Schemes that are
declared in `components.securitySchemes` but never used aren't flagged.

Threat model §9.3.

---

### `client-controlled-validation`

**The client decides whether its own request gets validated.**

The `validate` option accepts a predicate. If its result depends on anything the client sends, any client can
skip validation.

❌ [Vulnerable](examples/client-controlled-validation/vulnerable.js)

```js
new OpenAPIBackend({
  definition: './openapi.yml',
  // "skip validation for internal traffic"
  validate: (c, req) => !req.headers['x-internal-request'], // curl -H 'x-internal-request: 1' ...
});
```

✅ [Fixed](examples/client-controlled-validation/fixed.js): decide on something the client can't forge.

```js
validate: (c, req) => !isInternalNetwork(req.socket.remoteAddress),
```

Tracks `c.request` and the client-controlled parts of framework requests (Express, Lambda events) into the
predicate's return value, through helper functions and `if` statements.

Threat model §10.

---

### `client-controlled-operation`

**Client input picks the operation, response or example.**

`mockResponseForOperation` and `validateRequest(req, operationId)` trust their arguments and look them up in the
definition with plain property reads, with no allow-list.

❌ [Vulnerable](examples/client-controlled-operation/vulnerable.js)

```js
app.get('/mock/:operationId', (req, res) => {
  const { status, mock } = api.mockResponseForOperation(req.params.operationId, {
    example: req.query.example, // any example in the definition, internal ones included
  });
  res.status(status).json(mock);
});

api.validator.validateRequest(req, req.headers['x-operation-id']); // validate against a looser schema
```

✅ [Fixed](examples/client-controlled-operation/fixed.js): use the operation the router matched.

```js
notImplemented: (c) => c.api.mockResponseForOperation(c.operation.operationId),
```

Threat model §9.10.

---

### `untrusted-definition`

**The OpenAPI definition comes from a location the client influences.**

The definition is code. External `$ref`s get resolved at `init()`, reading local files and fetching URLs. A client
that controls the path can serve a definition with no `security:` at all, or use `$ref` for SSRF and local file
reads.

❌ [Vulnerable](examples/untrusted-definition/vulnerable.js)

```js
app.use('/tenants/:tenant', async (req, res) => {
  const api = new OpenAPIBackend({ definition: `./specs/${req.params.tenant}.yml` }); // ../../uploads/evil
  await api.init();
  return api.handleRequest(req, req, res);
});
```

✅ [Fixed](examples/untrusted-definition/fixed.js): load every definition at startup from an allow-list.

Threat model §9.7.

---

## How the examples are verified

Every file in [`examples/`](examples) marks the lines that must be flagged with a `// $ Alert` comment:

```js
deleteUser: (c) => users.delete(c.request.params.id), // $ Alert
```

CI checks the markers in two independent ways ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)):

1. **Unit tests.** `codeql test run` runs each query against its example directory, plus edge cases in
   [`tests/`](tests). A marker without an alert, or an alert without a marker, fails the build. Every `fixed.js` has
   no markers, so any alert there fails too.
2. **End to end.** CI builds a database from `examples/` and analyzes it the way you would: the query suite, the
   models pack, and CodeQL's built-in `js/sql-injection`. Then [`scripts/verify-sarif.mjs`](scripts/verify-sarif.mjs)
   checks the SARIF against the markers. A control run without the models pack confirms that the built-in query
   misses the SQL injection example on its own.

## Development

```sh
# once
for pack in queries models tests examples; do codeql pack install $pack; done

# compile, test, and check that the markers match
codeql query compile --check-only --warnings=error queries/src
codeql test run tests examples

# end to end, like CI
codeql database create db --language=javascript-typescript --source-root=examples
codeql database analyze db queries/openapi-backend.qls codeql/javascript-queries:Security/CWE-089/SqlInjection.ql \
  --model-packs=openapistack/openapi-backend-models --additional-packs=. --format=sarif-latest --output=results.sarif
node scripts/verify-sarif.mjs results.sarif examples
```

`codeql test run --learn` writes marker mismatches into the `.expected` files under a `testFailures` section, where
they'd pass from then on. CI rejects any `.expected` file with that section, so fix the query or the marker instead.

```
queries/
  openapistack/OpenApiBackend.qll   shared model: instances, options, handlers, the definition file
  src/<Query>/<Query>.ql, .md       queries and their help
models/openapi-backend.model.yml    models-as-data: c.request is a remote flow source
examples/<query-id>/                vulnerable.js, fixed.js, openapi.yml, with // $ Alert markers
tests/<Query>/                      edge cases: false positives we avoid, and setups we still catch
scripts/verify-sarif.mjs            end-to-end check of SARIF against the markers
```

## Contributing

Found a false positive or a misuse we missed? Open an issue with a minimal snippet. Every new query needs a threat model
reference, a `vulnerable.js` / `fixed.js` pair in `examples/`, and edge-case tests in `tests/`.

To report a security issue in openapi-backend itself, see its [SECURITY.md](https://github.com/openapistack/openapi-backend/blob/main/SECURITY.md).

## License

MIT
