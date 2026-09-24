# Client-controlled request validation

The `validate` option can be a predicate that decides per request whether to validate. If its result depends on data the client sends, such as a header, a query parameter or the body, any client can switch validation off for its own requests.

## Recommendation

Base the decision on something the client can't forge, like the connection's source address. If you rely on a header set by your proxy, make sure the proxy strips it from external traffic, and document that.

## Example

```js
new OpenAPIBackend({
  definition: './openapi.yml',
  validate: (c, req) => !req.headers['x-internal-request'], // curl -H 'x-internal-request: 1'
});
```

Fixed:

```js
new OpenAPIBackend({
  definition: './openapi.yml',
  validate: (c, req) => !isInternalNetwork(req.socket.remoteAddress),
});
```

## References

- [openapi-backend threat model §10](https://github.com/openapistack/openapi-backend/blob/main/docs/threat-model.md#10-how-does-this-library-get-misused)
- [Examples](https://github.com/openapistack/openapi-backend-codeql/tree/main/examples/client-controlled-validation)
