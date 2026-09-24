const { OpenAPIBackend } = require('openapi-backend');
const securityHandlers = require('./security');

new OpenAPIBackend({ definition: './openapi.yaml', securityHandlers: { oauth: () => true } }); // $ Alert
new OpenAPIBackend({ definition: './openapi.yaml', securityHandlers: { oauth: () => true, basic: () => true } });
// handlers we can't see: stay quiet
new OpenAPIBackend({ definition: './openapi.yaml', securityHandlers });
// definition not in the repository: stay quiet
new OpenAPIBackend({ definition: './missing.yaml', securityHandlers: {} });
