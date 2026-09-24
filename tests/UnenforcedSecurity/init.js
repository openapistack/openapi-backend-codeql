const { OpenAPIBackend } = require('openapi-backend');

// No definition in the repo: any registered security handler means auth is intended.
const main = async () => {
  const api = await new OpenAPIBackend({ // $ Alert
    definition: 'https://example.com/openapi.json',
    securityHandlers: { jwt: () => true },
  }).init();

  api.register({ getThing: (c) => c.request.params.id });
};

// No security handlers and no definition: nothing to enforce.
const open = new OpenAPIBackend({ definition: 'https://example.com/openapi.json' });
open.register('getThing', (c) => c.request.params.id);

main();
