# Client-controlled operation lookup

`mockResponseForOperation(operationId, { code, mediaType, example })` and `validateRequest(req, operationId)` trust their arguments. They look them up in the definition with plain property reads, with no allow-list. If the client supplies these values, it can:

- read any example or response in the definition, including ones never meant to be served
- validate its request against a different operation, with a looser schema

## Recommendation

Use the operation the router matched, `c.operation.operationId`, never a value from the request. If you really need a client-selected value, check it against an allow-list first.

## Example

```js
app.get('/mock/:operationId', (req, res) => {
  const { status, mock } = api.mockResponseForOperation(req.params.operationId, { example: req.query.example });
  res.status(status).json(mock);
});
```

Fixed:

```js
notImplemented: (c) => c.api.mockResponseForOperation(c.operation.operationId),
```

## References

- [openapi-backend threat model §9, item 10](https://github.com/openapistack/openapi-backend/blob/main/docs/threat-model.md#9-what-do-you-need-to-do)
- [Examples](https://github.com/openapistack/openapi-backend-codeql/tree/main/examples/client-controlled-operation)
