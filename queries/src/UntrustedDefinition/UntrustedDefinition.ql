/**
 * @name OpenAPI definition from untrusted location
 * @description Loading the OpenAPI definition from a path, URL or object the client influences lets
 *              the client replace your security requirements and schemas, or use external `$ref`s
 *              to read local files and make server-side requests.
 * @kind path-problem
 * @problem.severity error
 * @security-severity 9.1
 * @precision high
 * @id js/openapi-backend/untrusted-definition
 * @tags security
 *       external/cwe/cwe-73
 *       external/cwe/cwe-918
 */

import javascript
import openapistack.OpenApiBackend
import OpenApiBackend

module Config implements DataFlow::ConfigSig {
  predicate isSource(DataFlow::Node source) { source instanceof RemoteFlowSource }

  predicate isSink(DataFlow::Node sink) { sink = any(Backend b).getOption("definition") }
}

module Flow = TaintTracking::Global<Config>;

import Flow::PathGraph

from Flow::PathNode source, Flow::PathNode sink
where Flow::flowPath(source, sink)
select sink.getNode(), source, sink, "The OpenAPI definition is loaded from a location that $@ controls.",
  source.getNode(), "user input"
