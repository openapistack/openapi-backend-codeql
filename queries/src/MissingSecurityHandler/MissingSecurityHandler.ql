/**
 * @name Security scheme without a security handler
 * @description A security scheme used in the OpenAPI definition has no registered security handler,
 *              so every request that needs it fails authentication. Usually a sign that auth was
 *              never wired up.
 * @kind problem
 * @problem.severity warning
 * @security-severity 5.0
 * @precision high
 * @id js/openapi-backend/missing-security-handler
 * @tags security
 *       correctness
 *       external/cwe/cwe-862
 */

import javascript
import openapistack.OpenApiBackend
import OpenApiBackend

from Backend b, Spec spec, string scheme, SpecValue declaration
where
  spec = b.getSpec() and
  declaration = spec.getSecurityScheme(scheme) and
  spec.usesSecurityScheme(scheme) and
  not b.registersSecurityHandler(scheme, _) and
  not b.hasUnknownHandlers()
select b.getCalleeNode(), "Security scheme '" + scheme + "' is $@ but has no registered security handler.",
  declaration, "used in the definition"
