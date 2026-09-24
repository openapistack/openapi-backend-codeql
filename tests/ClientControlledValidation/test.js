const { OpenAPIBackend } = require('openapi-backend');

const def = 'https://example.com/openapi.json';

const isInternal = (req) => req.get('x-internal') === 'yes'; // $ Source
new OpenAPIBackend({ definition: def, validate: (c, req) => !isInternal(req) }); // $ Alert

function skipForDebug(c, event) {
  if (event.queryStringParameters.debug) { // $ Source
    return false; // $ Alert
  }
  return true; // $ Alert
}
new OpenAPIBackend({ definition: def, validate: skipForDebug });

// Not client-controlled
new OpenAPIBackend({ definition: def, validate: (c) => c.operation.operationId !== 'healthCheck' });
new OpenAPIBackend({ definition: def, validate: () => process.env.NODE_ENV !== 'test' });
new OpenAPIBackend({ definition: def, validate: (c, req) => req.socket.remoteAddress !== '127.0.0.1' });
