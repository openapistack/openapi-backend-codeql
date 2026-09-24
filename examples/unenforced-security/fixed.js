const { OpenAPIBackend } = require('openapi-backend');
const { verifyJwt, users, Unauthorized } = require('./app');

const securityHandlers = {
  jwt: (c) => verifyJwt(c.request.headers.authorization),
};

// Fix 1 (recommended): strict mode fails closed. handleRequest rejects with "401-unauthorized: ..."
const strictApi = new OpenAPIBackend({
  definition: './openapi.yml',
  strict: true,
  securityHandlers,
  handlers: {
    getUser: (c) => users.get(c.request.params.id),
    deleteUser: (c) => users.delete(c.request.params.id),
  },
});

// Fix 2: register an unauthorizedHandler. Unauthorized requests never reach operation handlers.
const apiWithHandler = new OpenAPIBackend({
  definition: './openapi.yml',
  securityHandlers,
  handlers: {
    unauthorizedHandler: (c, req, res) => res.status(401).json({ error: 'unauthorized' }),
    getUser: (c) => users.get(c.request.params.id),
    deleteUser: (c) => users.delete(c.request.params.id),
  },
});

// Fix 3: check c.security.authorized in every protected handler. Works, but easy to forget.
const requireAuth = (c) => {
  if (!c.security.authorized) throw new Unauthorized();
};

const apiWithChecks = new OpenAPIBackend({ definition: './openapi.yml', securityHandlers });
apiWithChecks.register({
  getUser: (c) => {
    requireAuth(c);
    return users.get(c.request.params.id);
  },
  deleteUser: (c) => {
    if (!c.security.authorized) throw new Unauthorized();
    return users.delete(c.request.params.id);
  },
});

module.exports = { strictApi, apiWithHandler, apiWithChecks };
