# Request validation not enforced

With `validate: true` (the default) openapi-backend *computes* whether a request matches the schema and records it in `c.validation`. It doesn't reject invalid requests by itself. In non-strict mode, without a `validationFail` (or `400`) handler, a request that fails validation still reaches the operation handler.

Handlers that rely on the schema to bound their input, such as enums, lengths or `additionalProperties: false`, then get data the schema was supposed to reject.

When the definition is in the repository, the query flags each handler for an operation that takes a request body or parameters. Otherwise it flags the `OpenAPIBackend` instance once, if no operation handler checks `c.validation`.

## Recommendation

Register a `validationFail` handler that returns a 400 response, or set `strict: true`. Or check `c.validation.valid` in the handler.

## Example

```js
const api = new OpenAPIBackend({ definition: './openapi.yml' });
api.register('createUser', (c) => users.insert(c.request.requestBody)); // { role: 'admin' } gets in
```

Fixed:

```js
api.register('validationFail', (c, req, res) => res.status(400).json({ errors: c.validation.errors }));
```

## References

- [openapi-backend threat model §8, false friend 2](https://github.com/openapistack/openapi-backend/blob/main/docs/threat-model.md#8-what-does-the-library-not-do)
- [Examples](https://github.com/openapistack/openapi-backend-codeql/tree/main/examples/unenforced-validation)
