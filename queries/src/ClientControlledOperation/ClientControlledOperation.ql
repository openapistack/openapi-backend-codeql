/**
 * @name Client-controlled operation lookup
 * @description Passing request data to `mockResponseForOperation` or `validateRequest` lets the
 *              client pick which operation, response or example the definition lookup uses.
 * @kind path-problem
 * @problem.severity error
 * @security-severity 6.5
 * @precision high
 * @id js/openapi-backend/client-controlled-operation
 * @tags security
 *       external/cwe/cwe-639
 *       external/cwe/cwe-915
 */

import javascript
import openapistack.OpenApiBackend
import OpenApiBackend

/** Holds if `sink` selects the operation, response or example used by openapi-backend. */
predicate isOperationSelector(DataFlow::Node sink, string what) {
  exists(DataFlow::MethodCallNode call | call.getMethodName() = "mockResponseForOperation" |
    sink = call.getArgument(0) and what = "operation"
    or
    sink = call.getArgument(1) and what = "mock options"
    or
    exists(string option | option = ["code", "mediaType", "example"] |
      sink = call.getOptionArgument(1, option) and what = "'" + option + "' option"
    )
  )
  or
  exists(Backend b, DataFlow::MethodCallNode call |
    call = [b.ref(), b.ref().getAPropertyRead("validator")].getAMethodCall("validateRequest") and
    sink = call.getArgument(1) and
    what = "operation"
  )
}

module Config implements DataFlow::ConfigSig {
  predicate isSource(DataFlow::Node source) { source instanceof RemoteFlowSource }

  predicate isSink(DataFlow::Node sink) { isOperationSelector(sink, _) }
}

module Flow = TaintTracking::Global<Config>;

import Flow::PathGraph

from Flow::PathNode source, Flow::PathNode sink, string what
where Flow::flowPath(source, sink) and isOperationSelector(sink.getNode(), what)
select sink.getNode(), source, sink, "$@ selects the " + what + " for this definition lookup.",
  source.getNode(), "User input"
