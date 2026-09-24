// "Skip validation for internal traffic." But the client decides what counts as internal:
//   curl -H 'x-internal-request: 1' https://api.example.com/users -d '{"role":"admin"}'
const { OpenAPIBackend } = require('openapi-backend');

const api = new OpenAPIBackend({
  definition: './openapi.yml',
  validate: (c, req) => !req.headers['x-internal-request'], // $ Alert
});

// Same thing, read from the context instead of the framework request
const other = new OpenAPIBackend({
  definition: './openapi.yml',
  validate: (c) => c.request.query.debug !== 'true', // $ Alert
});

module.exports = { api, other };
