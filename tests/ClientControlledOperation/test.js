const express = require('express');
const OpenAPIBackend = require('openapi-backend').default;
const { validator } = require('some-other-validator');

const app = express();

const main = async () => {
  const api = await new OpenAPIBackend({ definition: './openapi.yml' }).init();

  app.post('/validate', (req, res) => {
    res.json(api.validateRequest(req, req.body.operationId)); // $ Alert
  });

  // not openapi-backend: same method name on another library
  app.post('/other', (req, res) => {
    res.json(validator.validateRequest(req, req.query.schema));
  });

  // the whole options object from the client
  app.get('/mock', (req, res) => res.json(api.mockResponseForOperation('getPets', req.query))); // $ Alert
};

main();
