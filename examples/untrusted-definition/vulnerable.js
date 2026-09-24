// Multi-tenant API that loads each tenant's definition on demand.
//   GET /tenants/..%2F..%2Fuploads%2Fevil/anything
// loads a definition the attacker uploaded: no security requirements, no schemas, and
// external $refs that read local files or fetch internal URLs.
const express = require('express');
const { OpenAPIBackend } = require('openapi-backend');

const app = express();

app.use('/tenants/:tenant', async (req, res, next) => {
  try {
    const api = new OpenAPIBackend({ definition: `./specs/${req.params.tenant}.yml` }); // $ Alert
    await api.init();
    await api.handleRequest(req, req, res);
  } catch (err) {
    next(err);
  }
});

app.listen(3000);
