/**
 * @name Client-controlled request validation
 * @description A `validate` predicate that depends on request data lets any client decide
 *              whether its own request gets validated.
 * @kind path-problem
 * @problem.severity error
 * @security-severity 7.5
 * @precision high
 * @id js/openapi-backend/client-controlled-validation
 * @tags security
 *       external/cwe/cwe-807
 *       external/cwe/cwe-290
 */

import javascript
import openapistack.OpenApiBackend
import OpenApiBackend

/** Gets a function passed as the `validate` option. */
DataFlow::FunctionNode validatePredicate() {
  result = any(Backend b).getOption("validate").getAFunctionValue()
}

/** Gets a property of a raw framework request that the client controls. */
string clientControlledProperty() {
  result =
    [
      "headers", "query", "body", "cookies", "params", "url", "path", "originalUrl", "hostname",
      "host", "rawHeaders", "queryStringParameters", "pathParameters", "multiValueHeaders"
    ]
}

/**
 * Gets a reference to a request object passed to a `validate` predicate: `context.request` or a
 * handler argument, typically the framework's request. Tracked into helper functions.
 */
DataFlow::SourceNode requestObject(DataFlow::TypeTracker t) {
  t.start() and
  exists(DataFlow::FunctionNode validator | validator = validatePredicate() |
    result = validator.getParameter(0).getAPropertyRead("request")
    or
    result = validator.getParameter(any(int i | i >= 1))
  )
  or
  exists(DataFlow::TypeTracker t2 | result = requestObject(t2).track(t2, t))
}

/** Gets a reference to a request object passed to a `validate` predicate. */
DataFlow::SourceNode requestObject() { result = requestObject(DataFlow::TypeTracker::end()) }

/** Holds if `node` is after `stmt` in the source text. */
predicate isAfter(DataFlow::Node node, Stmt stmt) {
  exists(Location n, Location s | n = node.getAstNode().getLocation() and s = stmt.getLocation() |
    n.getStartLine() > s.getStartLine()
    or
    n.getStartLine() = s.getStartLine() and n.getStartColumn() > s.getStartColumn()
  )
}

module Config implements DataFlow::ConfigSig {
  predicate isSource(DataFlow::Node source) {
    // context.request
    source = validatePredicate().getParameter(0).getAPropertyRead("request")
    or
    // client-controlled parts of the framework request
    source = requestObject().getAPropertyRead(clientControlledProperty())
    or
    source = requestObject().getAMethodCall(["get", "header"])
  }

  predicate isSink(DataFlow::Node sink) { sink = validatePredicate().getAReturn() }

  /** The predicate's result depends on the input, even when it's a boolean derived from it. */
  predicate isAdditionalFlowStep(DataFlow::Node pred, DataFlow::Node succ) {
    exists(Expr e | e = succ.asExpr() |
      pred.asExpr() = e.(UnaryExpr).getOperand()
      or
      pred.asExpr() = e.(BinaryExpr).getAnOperand()
      or
      pred.asExpr() = e.(ConditionalExpr).getCondition()
      or
      pred.asExpr() = e.(MethodCallExpr).getReceiver()
      or
      pred.asExpr() = e.(InvokeExpr).getAnArgument()
    )
    or
    // `if (req.query.debug) return false; return true;`
    exists(DataFlow::FunctionNode validator, IfStmt guard |
      validator = validatePredicate() and
      guard.getContainer() = validator.getFunction() and
      pred.asExpr() = guard.getCondition() and
      succ = validator.getAReturn() and
      isAfter(succ, guard)
    )
  }
}

module Flow = TaintTracking::Global<Config>;

import Flow::PathGraph

from Flow::PathNode source, Flow::PathNode sink
where Flow::flowPath(source, sink)
select sink.getNode(), source, sink,
  "Whether this request gets validated depends on $@, which the client controls.", source.getNode(),
  "request data"
