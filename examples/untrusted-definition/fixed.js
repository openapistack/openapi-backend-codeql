const express = require('express');
const { OpenAPIBackend } = require('openapi-backend');

const TENANTS = ['acme', 'globex'];

// Load every definition at startup from a fixed allow-list, then pick one per request.
const main = async () => {
  const apis = {};
  for (const tenant of TENANTS) {
    apis[tenant] = await new OpenAPIBackend({ definition: `./specs/${tenant}.yml` }).init();
  }

  const app = express();
  app.use('/tenants/:tenant', (req, res, next) => {
    const api = apis[req.params.tenant];
    if (!api) return res.sendStatus(404);
    return api.handleRequest(req, req, res).catch(next);
  });
  app.listen(3000);
};

main();
