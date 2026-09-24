// A "mock" endpoint that lets the client name any operation, status code and example
// in the definition, including internal ones that were never meant to be served.
const express = require('express');
const { OpenAPIBackend } = require('openapi-backend');

const api = new OpenAPIBackend({ definition: './openapi.yml' });
const app = express();

app.get('/mock/:operationId', (req, res) => {
  const { status, mock } = api.mockResponseForOperation(req.params.operationId, { // $ Alert
    code: req.query.status, // $ Alert
    example: req.query.example, // $ Alert
  });
  res.status(status).json(mock);
});

// Validates the request against whichever operation the client names,
// for example one with a looser schema than the route it actually hit.
app.post('/users', (req, res) => {
  const result = api.validator.validateRequest(req, req.headers['x-operation-id']); // $ Alert
  res.status(result.valid ? 200 : 400).end();
});

app.listen(3000);
