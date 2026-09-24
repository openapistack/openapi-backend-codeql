const express = require('express');
const { OpenAPIBackend } = require('openapi-backend');

// Use the operation the router matched, never one the client names.
const api = new OpenAPIBackend({
  definition: './openapi.yml',
  handlers: {
    notImplemented: (c, req, res) => {
      const { status, mock } = c.api.mockResponseForOperation(c.operation.operationId);
      return res.status(status).json(mock);
    },
  },
});

const app = express();
app.use((req, res, next) => api.handleRequest(req, req, res).catch(next));
app.listen(3000);
