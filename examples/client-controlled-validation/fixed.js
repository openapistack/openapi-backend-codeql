const { OpenAPIBackend } = require('openapi-backend');
const { isInternalNetwork } = require('./network');

// Decide on something the client can't forge, like the connection's source address.
// (If you're behind a proxy, strip x-internal-request at the edge and document that you did.)
const api = new OpenAPIBackend({
  definition: './openapi.yml',
  validate: (c, req) => !isInternalNetwork(req.socket.remoteAddress),
});

module.exports = api;
