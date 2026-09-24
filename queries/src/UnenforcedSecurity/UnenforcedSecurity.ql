/**
 * @name Security requirements not enforced
 * @description openapi-backend calls the operation handler even when a request fails its security
 *              requirements, unless an unauthorizedHandler is registered or strict mode is on.
 * @kind problem
 * @problem.severity error
 * @security-severity 8.8
 * @precision high
 * @id js/openapi-backend/unenforced-security
 * @tags security
 *       external/cwe/cwe-862
 *       external/cwe/cwe-285
 */

import javascript
import openapistack.OpenApiBackend
import OpenApiBackend

/** Holds if nothing on `b` rejects a request that fails its security requirements. */
predicate isUnenforced(Backend b) {
  not b.mayBeStrict() and
  not b.hasHandler("unauthorizedHandler") and
  not b.hasUnknownHandlers() and
  not readsProperty(b.getLifecycleHandler(["postSecurityHandler", "preOperationHandler"])
        .getFunction(), "authorized")
}

from Backend b, DataFlow::Node alert, string message
where
  isUnenforced(b) and
  (
    // The definition is in the repository: flag each handler of an operation that requires auth.
    exists(Spec spec, string operationId, DataFlow::FunctionNode handler |
      spec = b.getSpec() and
      handler = b.getOperationHandler(operationId) and
      spec.requiresSecurity(spec.getOperation(operationId)) and
      not readsProperty(handler.getFunction(), "authorized") and
      alert = handler and
      message =
        "This handler for '" + operationId +
          "' runs even when the request fails its security requirements, because $@ has no unauthorizedHandler and strict mode is off."
    )
    or
    // No definition to read: flag the instance once, if security handlers are registered and no
    // operation handler looks at the result.
    not exists(b.getSpec()) and
    b.hasSecurityHandlers() and
    exists(b.getOperationHandler(_)) and
    b.allOperationHandlersKnown() and
    not readsProperty(b.getOperationHandler(_).getFunction(), "authorized") and
    alert = b.getCalleeNode() and
    message =
      "$@ registers security handlers but never enforces them: there is no unauthorizedHandler, strict mode is off, and no operation handler checks c.security.authorized."
  )
select alert, message, b, "This OpenAPIBackend instance"
