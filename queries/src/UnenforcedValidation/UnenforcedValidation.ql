/**
 * @name Request validation not enforced
 * @description openapi-backend calls the operation handler even when a request fails schema
 *              validation, unless a validationFail handler is registered or strict mode is on.
 * @kind problem
 * @problem.severity warning
 * @security-severity 6.5
 * @precision high
 * @id js/openapi-backend/unenforced-validation
 * @tags security
 *       external/cwe/cwe-20
 */

import javascript
import openapistack.OpenApiBackend
import OpenApiBackend

/** Holds if nothing on `b` rejects a request that fails validation. */
predicate isUnenforced(Backend b) {
  b.mayValidate() and
  not b.mayBeStrict() and
  not b.hasHandler(["validationFail", "400"]) and
  not b.hasUnknownHandlers() and
  not readsProperty(b.getLifecycleHandler("preOperationHandler").getFunction(), "validation")
}

/** Holds if `handler` uses the request, so it depends on validation having happened. */
predicate usesRequest(DataFlow::FunctionNode handler) {
  exists(handler.getParameter(0).getAPropertyRead("request"))
}

from Backend b, DataFlow::Node alert, string message
where
  isUnenforced(b) and
  (
    // The definition is in the repository: flag each handler of an operation that takes input.
    exists(Spec spec, string operationId, DataFlow::FunctionNode handler |
      spec = b.getSpec() and
      handler = b.getOperationHandler(operationId) and
      spec.hasInput(spec.getOperation(operationId)) and
      usesRequest(handler) and
      not readsProperty(handler.getFunction(), "validation") and
      alert = handler and
      message =
        "This handler for '" + operationId +
          "' runs even when the request fails validation, because $@ has no validationFail handler and strict mode is off."
    )
    or
    // No definition to read: flag the instance once, if handlers use the request and none of
    // them looks at the validation result.
    not exists(b.getSpec()) and
    usesRequest(b.getOperationHandler(_)) and
    b.allOperationHandlersKnown() and
    not readsProperty(b.getOperationHandler(_).getFunction(), "validation") and
    alert = b.getCalleeNode() and
    message =
      "$@ validates requests but never enforces the result: there is no validationFail handler, strict mode is off, and no operation handler checks c.validation."
  )
select alert, message, b, "This OpenAPIBackend instance"
