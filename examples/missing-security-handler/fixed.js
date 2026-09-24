const { OpenAPIBackend } = require('openapi-backend');
const { verifyJwt, apiKeys } = require('./auth');

const api = new OpenAPIBackend({
  definition: './openapi.yml',
  strict: true,
  securityHandlers: {
    jwt: (c) => verifyJwt(c.request.headers.authorization),
    apiKey: (c) => apiKeys.lookup(c.request.headers['x-api-key']),
  },
});

module.exports = api;
