const { OpenAPIBackend } = require('openapi-backend');
const handlers = require('./handlers');
const { requireAuth } = require('./auth');

const securityHandlers = { jwt: () => true };

// strict comes from the environment: might be on, stay quiet.
const envStrict = new OpenAPIBackend({
  definition: 'https://example.com/openapi.json',
  strict: process.env.STRICT !== 'false',
  securityHandlers,
  handlers: { getThing: (c) => c.request.params.id },
});

// Handlers imported from another module: unauthorizedHandler might be among them.
const imported = new OpenAPIBackend({ definition: 'https://example.com/openapi.json', securityHandlers, handlers });
imported.register('getThing', (c) => c.request.params.id);

// Handlers spread from another object: same.
const spread = new OpenAPIBackend({
  definition: 'https://example.com/openapi.json',
  securityHandlers,
  handlers: { ...handlers, getThing: (c) => c.request.params.id },
});

// unauthorizedHandler registered later, via registerHandler.
const later = new OpenAPIBackend({ definition: 'https://example.com/openapi.json', securityHandlers });
later.register('getThing', (c) => c.request.params.id);
later.registerHandler('unauthorizedHandler', () => ({ statusCode: 401 }));

// Enforced once in postSecurityHandler.
const hook = new OpenAPIBackend({ definition: 'https://example.com/openapi.json', securityHandlers });
hook.register({
  postSecurityHandler: (c) => {
    if (!c.security.authorized) throw new Error('401');
  },
  getThing: (c) => c.request.params.id,
});

// Checked with destructuring, and through an imported helper wrapper.
const destructured = new OpenAPIBackend({ definition: 'https://example.com/openapi.json', securityHandlers });
destructured.register({
  getThing: (c) => {
    const { authorized } = c.security;
    return authorized ? c.request.params.id : null;
  },
  getOther: requireAuth((c) => c.request.params.id),
});

// Explicit strict: false is still not strict.
const explicit = new OpenAPIBackend({ definition: 'https://example.com/openapi.json', strict: false, securityHandlers }); // $ Alert
explicit.register('getThing', (c) => c.request.params.id);

// No definition to read, but one handler checks authorized: the author knows, stay quiet.
const partly = new OpenAPIBackend({ definition: 'https://example.com/openapi.json', securityHandlers });
partly.register({
  getPublic: (c) => 'hello',
  getPrivate: (c) => (c.security.authorized ? c.request.params.id : null),
});
