# Security scheme without a security handler

The definition uses a security scheme, but no security handler is registered for it. openapi-backend treats an unregistered scheme as failed, so every request that needs it fails authentication. That's safe on its own, but usually a sign that auth was never wired up.

If the failure isn't enforced either (see `js/openapi-backend/unenforced-security`), the operation is open to anyone.

This query reads the definition when the `definition` option is a constant path, or `path.join(__dirname, ...)`, pointing at a YAML or JSON file in the repository. Schemes declared under `components.securitySchemes` but never used in a `security` requirement are ignored.

## Recommendation

Register a security handler for every scheme your definition uses, with `securityHandlers` or `registerSecurityHandler`.

## Example

```js
// openapi.yml uses both jwt and apiKey
const api = new OpenAPIBackend({ definition: './openapi.yml' });
api.registerSecurityHandler('jwt', verifyJwt); // apiKey is never registered
```

## References

- [openapi-backend threat model §9, item 3](https://github.com/openapistack/openapi-backend/blob/main/docs/threat-model.md#9-what-do-you-need-to-do)
- [Examples](https://github.com/openapistack/openapi-backend-codeql/tree/main/examples/missing-security-handler)
