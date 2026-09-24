# Security requirements not enforced

openapi-backend runs your security handlers and records the verdict in `c.security.authorized`. It doesn't reject the request by itself. In the default non-strict mode, a request that fails its security requirements still reaches the operation handler unless an `unauthorizedHandler` is registered. The library logs a warning once and carries on.

An operation that declares `security:` in the OpenAPI definition but never checks `c.security.authorized` is open to anyone.

## Recommendation

Do one of these:

- Set `strict: true`. `handleRequest` then rejects with `401-unauthorized: ...` for requests that fail their security requirements.
- Register an `unauthorizedHandler` that returns a 401 response.
- Check `c.security.authorized` at the top of every protected handler, or once in a `postSecurityHandler`.

## Example

```js
const api = new OpenAPIBackend({
  definition: './openapi.yml', // deleteUser requires a JWT
  securityHandlers: { jwt: (c) => verifyJwt(c.request.headers.authorization) },
  handlers: {
    deleteUser: (c) => users.delete(c.request.params.id), // runs for invalid tokens too
  },
});
```

Fixed:

```js
const api = new OpenAPIBackend({ definition: './openapi.yml', strict: true, securityHandlers, handlers });
```

## References

- [openapi-backend threat model §8 and §9](https://github.com/openapistack/openapi-backend/blob/main/docs/threat-model.md#8-what-does-the-library-not-do)
- GHSA-7mmm-8m7g-cp5g
- [Examples](https://github.com/openapistack/openapi-backend-codeql/tree/main/examples/unenforced-security)
