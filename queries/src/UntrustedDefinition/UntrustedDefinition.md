# OpenAPI definition from untrusted location

The OpenAPI definition decides which operations exist, which security requirements apply and what validation does. When loading it, openapi-backend resolves external `$ref`s by reading local files and fetching URLs.

If the client influences the definition's path, URL or content, it can:

- serve an API with no security requirements or schemas
- read local files or make server-side requests through `$ref`

## Recommendation

Treat the definition as code. Load it from a fixed path or object you control, ideally once at startup. For multi-tenant setups, load every tenant's definition up front from an allow-list and pick one per request.

## Example

```js
app.use('/tenants/:tenant', async (req, res) => {
  const api = new OpenAPIBackend({ definition: `./specs/${req.params.tenant}.yml` }); // ../../uploads/evil
  await api.init();
  return api.handleRequest(req, req, res);
});
```

## References

- [openapi-backend threat model §9, item 7](https://github.com/openapistack/openapi-backend/blob/main/docs/threat-model.md#9-what-do-you-need-to-do)
- [Examples](https://github.com/openapistack/openapi-backend-codeql/tree/main/examples/untrusted-definition)
