// Every operation except getHealth requires a JWT (see openapi.yml).
// The security handler runs and fails for a bad token, but nothing rejects the request:
// openapi-backend logs a warning and calls the operation handler anyway.
const { OpenAPIBackend } = require('openapi-backend');
const { verifyJwt, users } = require('./app');

const api = new OpenAPIBackend({
  definition: './openapi.yml',
  securityHandlers: {
    jwt: (c) => verifyJwt(c.request.headers.authorization),
  },
  handlers: {
    getHealth: () => ({ status: 'ok' }), // public, so not flagged
    getUser: (c) => users.get(c.request.params.id), // $ Alert
    deleteUser: (c) => users.delete(c.request.params.id), // $ Alert
  },
});

module.exports = api;
