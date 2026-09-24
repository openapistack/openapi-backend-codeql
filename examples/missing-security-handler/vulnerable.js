// openapi.yml uses two schemes: jwt everywhere, and apiKey for exportReports.
// Only jwt is wired up. Every call to exportReports fails authentication, and if
// that failure isn't enforced either, nobody notices it was never checked at all.
const { OpenAPIBackend } = require('openapi-backend');
const { verifyJwt } = require('./auth');

const api = new OpenAPIBackend({ definition: './openapi.yml', strict: true }); // $ Alert
api.registerSecurityHandler('jwt', (c) => verifyJwt(c.request.headers.authorization));

module.exports = api;
