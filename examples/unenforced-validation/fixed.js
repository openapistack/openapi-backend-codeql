const { OpenAPIBackend } = require('openapi-backend');
const { users } = require('./app');

// Fix 1: register a validationFail handler. Invalid requests never reach operation handlers.
const api = new OpenAPIBackend({ definition: './openapi.yml' });
api.register({
  validationFail: (c, req, res) => res.status(400).json({ errors: c.validation.errors }),
  createUser: (c) => users.insert(c.request.requestBody),
});

// Fix 2: strict mode. handleRequest rejects with "400-validationFail: ..."
const strictApi = new OpenAPIBackend({
  definition: './openapi.yml',
  strict: true,
  handlers: { createUser: (c) => users.insert(c.request.requestBody) },
});

module.exports = { api, strictApi };
