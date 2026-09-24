# Changelog

## 0.1.0 (unreleased)

First release.

### Queries (`openapistack/openapi-backend-queries`)

- `js/openapi-backend/unenforced-security`: operation handlers that run when security requirements fail
- `js/openapi-backend/unenforced-validation`: operation handlers that run when request validation fails
- `js/openapi-backend/missing-security-handler`: security schemes used in the definition with no registered handler
- `js/openapi-backend/client-controlled-validation`: `validate` predicates that depend on request data
- `js/openapi-backend/client-controlled-operation`: request data selecting the operation, response or example in `mockResponseForOperation` / `validateRequest`
- `js/openapi-backend/untrusted-definition`: OpenAPI definitions loaded from a client-influenced location

### Models (`openapistack/openapi-backend-models`)

- `context.request` in operation handlers, security handlers, lifecycle handlers and `validate` predicates is a remote flow source
