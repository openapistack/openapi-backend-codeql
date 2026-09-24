/**
 * Provides classes for reasoning about how `openapi-backend` is configured and used:
 * `OpenAPIBackend` instances, their options, registered handlers and, when it can be found
 * in the repository, the OpenAPI definition they serve.
 */

import javascript

module OpenApiBackend {
  /** Gets a name of a handler that openapi-backend calls itself, rather than for an operation. */
  string lifecycleHandlerName() {
    result =
      [
        "404", "notFound", "405", "methodNotAllowed", "501", "notImplemented", "400",
        "validationFail", "unauthorizedHandler", "preRoutingHandler", "postRoutingHandler",
        "postSecurityHandler", "preOperationHandler", "postResponseHandler"
      ]
  }

  /** Gets an HTTP method key of an OpenAPI path item. */
  string httpMethod() {
    result = ["get", "put", "post", "delete", "options", "head", "patch", "trace"]
  }

  /** Gets an API node for the `OpenAPIBackend` class. */
  API::Node backendClass() {
    result = API::moduleImport("openapi-backend").getMember(["OpenAPIBackend", "default"])
    or
    result = API::moduleImport("openapi-backend")
  }

  /** Holds if `n` is an object literal without spread properties, so its keys are all known. */
  bindingset[n]
  private predicate hasKnownKeys(DataFlow::Node n) {
    exists(ObjectExpr o | o = n.getALocalSource().asExpr() |
      not o.getAProperty() instanceof SpreadProperty
    )
  }

  /** Holds if `n` is inside function `f`, possibly nested in a closure. */
  bindingset[f]
  private predicate isWithin(AstNode n, Function f) { n.getContainer().getEnclosingContainer*() = f }

  /**
   * Holds if function `f`, or a function it calls, reads a property named `prop`.
   *
   * Following calls lets a handler delegate a check like `c.security.authorized` to a helper.
   */
  predicate readsProperty(Function f, string prop) {
    exists(DataFlow::PropRead r |
      r.getPropertyName() = prop and
      isWithin(r.getAstNode(), f)
    )
    or
    exists(DataFlow::InvokeNode call, Function g |
      isWithin(call.asExpr(), f) and
      g = call.getACallee() and
      g != f and
      readsProperty(g, prop)
    )
  }

  /** A `new OpenAPIBackend(...)` expression. */
  class Backend extends DataFlow::NewNode {
    Backend() { this = backendClass().getAnInstantiation() }

    /** Gets the value of the constructor option `name`. */
    DataFlow::Node getOption(string name) { result = this.getOptionArgument(0, name) }

    private DataFlow::SourceNode ref(DataFlow::TypeTracker t) {
      t.start() and result = this
      or
      t.startInPromise() and result = this.ref().getAMethodCall("init")
      or
      exists(DataFlow::TypeTracker t2 | result = this.ref(t2).track(t2, t))
    }

    /** Gets a reference to this instance, including the awaited result of `init()`. */
    DataFlow::SourceNode ref() { result = this.ref(DataFlow::TypeTracker::end()) }

    /** Gets a call to `register`, `registerHandler` or `registerSecurityHandler` on this instance. */
    DataFlow::MethodCallNode getARegisterCall(string method) {
      method = ["register", "registerHandler", "registerSecurityHandler"] and
      result = this.ref().getAMethodCall(method)
    }

    /**
     * Holds if `handler` is registered as an operation or lifecycle handler named `name`,
     * in the constructor or with `register` / `registerHandler`.
     */
    predicate registersHandler(string name, DataFlow::Node handler) {
      handler = this.getOption("handlers").getALocalSource().getAPropertyWrite(name).getRhs()
      or
      exists(DataFlow::MethodCallNode call | call = this.getARegisterCall(["register", "registerHandler"]) |
        call.getNumArgument() = 2 and
        name = call.getArgument(0).getStringValue() and
        handler = call.getArgument(1)
        or
        call.getNumArgument() = 1 and
        handler = call.getArgument(0).getALocalSource().getAPropertyWrite(name).getRhs()
      )
    }

    /** Holds if `handler` is registered as the security handler for scheme `name`. */
    predicate registersSecurityHandler(string name, DataFlow::Node handler) {
      handler =
        this.getOption("securityHandlers").getALocalSource().getAPropertyWrite(name).getRhs()
      or
      exists(DataFlow::MethodCallNode call | call = this.getARegisterCall("registerSecurityHandler") |
        name = call.getArgument(0).getStringValue() and
        handler = call.getArgument(1)
      )
    }

    /** Holds if a handler named `name` is registered. */
    predicate hasHandler(string name) { this.registersHandler(name, _) }

    /** Holds if at least one security handler is registered. */
    predicate hasSecurityHandlers() { this.registersSecurityHandler(_, _) }

    /** Gets a function registered as the operation handler for `operationId`. */
    DataFlow::FunctionNode getOperationHandler(string operationId) {
      exists(DataFlow::Node h |
        this.registersHandler(operationId, h) and
        not operationId = lifecycleHandlerName() and
        result = h.getAFunctionValue()
      )
    }

    /** Gets a function registered as the lifecycle handler `name`. */
    DataFlow::FunctionNode getLifecycleHandler(string name) {
      exists(DataFlow::Node h |
        this.registersHandler(name, h) and
        name = lifecycleHandlerName() and
        result = h.getAFunctionValue()
      )
    }

    /** Gets a function registered as the security handler for scheme `name`. */
    DataFlow::FunctionNode getSecurityHandler(string name) {
      exists(DataFlow::Node h |
        this.registersSecurityHandler(name, h) and
        result = h.getAFunctionValue()
      )
    }

    /**
     * Holds if some handlers are registered in a way we can't enumerate, for example a
     * `handlers` object imported from another module or built with spread properties.
     *
     * Queries that alert on a *missing* handler stay quiet in that case.
     */
    predicate hasUnknownHandlers() {
      not hasKnownKeys(this.getArgument(0))
      or
      exists(DataFlow::Node h | h = this.getOption(["handlers", "securityHandlers"]) |
        not hasKnownKeys(h)
      )
      or
      exists(DataFlow::MethodCallNode call | call = this.getARegisterCall(_) |
        call.getNumArgument() = 1 and not hasKnownKeys(call.getArgument(0))
        or
        call.getNumArgument() >= 2 and not exists(call.getArgument(0).getStringValue())
      )
    }

    /** Holds if every operation handler is a function we can see into. */
    predicate allOperationHandlersKnown() {
      forall(string operationId, DataFlow::Node h |
        this.registersHandler(operationId, h) and not operationId = lifecycleHandlerName()
      |
        exists(h.getAFunctionValue())
      )
    }

    /** Holds if strict mode may be on, i.e. the `strict` option is anything but a literal `false`. */
    predicate mayBeStrict() {
      exists(DataFlow::Node s | s = this.getOption("strict") |
        not s.asExpr().(BooleanLiteral).getValue() = "false"
      )
      or
      exists(this.ref().getAPropertyWrite("strict"))
    }

    /** Holds if request validation may be on, i.e. `validate` is not a literal `false`. */
    predicate mayValidate() {
      not this.getOption("validate").asExpr().(BooleanLiteral).getValue() = "false"
    }

    /** Gets the path of the definition file, when `definition` is a constant path. */
    string getDefinitionPath() {
      result = this.getOption("definition").getStringValue()
      or
      exists(DataFlow::CallNode join |
        join = DataFlow::moduleMember("path", ["join", "resolve"]).getACall() and
        join = this.getOption("definition").getALocalSource() and
        join.getArgument(0).asExpr().(VarAccess).getName() = "__dirname" and
        forall(int i | i in [1 .. join.getNumArgument() - 1] |
          exists(join.getArgument(i).getStringValue())
        ) and
        result =
          concat(int i, string s |
            i > 0 and s = join.getArgument(i).getStringValue()
          |
            s, "/" order by i
          )
      )
    }

    /** Gets the definition file this instance loads, if it's in the repository. */
    File getDefinitionFile() {
      exists(string p, string candidate |
        p = this.getDefinitionPath() and
        result.getExtension() = ["yml", "yaml", "json"]
      |
        candidate = this.getFile().getParentContainer().getAbsolutePath() + "/" + p and
        result.getAbsolutePath() = normalizePath(candidate)
      )
    }

    /** Gets the root object of the definition this instance serves, if it's in the repository. */
    Spec getSpec() { result.getFile() = this.getDefinitionFile() }
  }

  /** Collapses `/./` and `dir/../` segments in an absolute path. */
  bindingset[path]
  private string normalizePath(string path) {
    result =
      path.regexpReplaceAll("/\\./", "/")
          .regexpReplaceAll("/[^/]+/\\.\\./", "/")
          .regexpReplaceAll("/[^/]+/\\.\\./", "/")
          .regexpReplaceAll("/[^/]+/\\.\\./", "/")
  }

  /** A YAML or JSON value in an OpenAPI definition file. */
  class SpecValue extends Locatable {
    SpecValue() { this instanceof YamlValue or this instanceof JsonValue }

    /** Gets the value of the mapping entry or object property `key`. */
    SpecValue getMember(string key) {
      result = this.(YamlMapping).lookup(key) or result = this.(JsonObject).getPropValue(key)
    }

    /** Gets a key of this mapping or object. */
    string getAKey() { exists(this.getMember(result)) }

    /** Gets the `i`th element of this sequence or array. */
    SpecValue getElement(int i) {
      result = this.(YamlSequence).getElement(i) or result = this.(JsonArray).getElementValue(i)
    }

    /** Gets the string value of this scalar. */
    string getStringValue() {
      result = this.(YamlScalar).getValue() or result = this.(JsonValue).getStringValue()
    }

    override string toString() {
      result = this.(YamlValue).toString() or result = this.(JsonValue).toString()
    }
  }

  /** The root object of an OpenAPI 3.x definition. */
  class Spec extends SpecValue {
    Spec() { exists(this.getMember("openapi").getStringValue()) and exists(this.getMember("paths")) }

    /** Gets the operation object for `operationId`. */
    SpecValue getOperation(string operationId) {
      result = this.getMember("paths").getMember(_).getMember(httpMethod()) and
      operationId = result.getMember("operationId").getStringValue()
    }

    /** Gets the security requirement list that applies to `operation`. */
    SpecValue getEffectiveSecurity(SpecValue operation) {
      operation = this.getOperation(_) and
      if exists(operation.getMember("security"))
      then result = operation.getMember("security")
      else result = this.getMember("security")
    }

    /**
     * Holds if `operation` requires authentication: at least one security requirement applies,
     * and none of them is the anonymous `{}` requirement.
     */
    predicate requiresSecurity(SpecValue operation) {
      exists(SpecValue requirements | requirements = this.getEffectiveSecurity(operation) |
        exists(requirements.getElement(_)) and
        not exists(SpecValue anonymous | anonymous = requirements.getElement(_) |
          not exists(anonymous.getAKey())
        )
      )
    }

    /** Holds if `operation` has a request body or parameters to validate. */
    predicate hasInput(SpecValue operation) {
      operation = this.getOperation(_) and
      (
        exists(operation.getMember(["requestBody", "parameters"]))
        or
        exists(SpecValue pathItem |
          pathItem = this.getMember("paths").getMember(_) and
          operation = pathItem.getMember(_) and
          exists(pathItem.getMember("parameters"))
        )
      )
    }

    /** Gets the declaration of security scheme `name` under `components.securitySchemes`. */
    SpecValue getSecurityScheme(string name) {
      result = this.getMember("components").getMember("securitySchemes").getMember(name)
    }

    /** Holds if some security requirement, global or per operation, names scheme `name`. */
    predicate usesSecurityScheme(string name) {
      exists(SpecValue requirements |
        requirements = this.getMember("security") or
        requirements = this.getOperation(_).getMember("security")
      |
        exists(requirements.getElement(_).getMember(name))
      )
    }
  }

  /**
   * A read of `context.request` in a handler, a security handler or a `validate` predicate.
   *
   * Everything under it comes straight from the HTTP request.
   */
  class RequestRead extends RemoteFlowSource {
    RequestRead() {
      exists(Backend b, DataFlow::FunctionNode handler |
        handler = b.getOperationHandler(_) or
        handler = b.getLifecycleHandler(_) or
        handler = b.getSecurityHandler(_) or
        handler = b.getOption("validate").getAFunctionValue()
      |
        this = handler.getParameter(0).getAPropertyRead("request")
      )
    }

    override string getSourceType() { result = "openapi-backend request" }
  }
}
