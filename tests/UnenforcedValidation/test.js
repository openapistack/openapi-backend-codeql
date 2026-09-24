const { OpenAPIBackend } = require('openapi-backend');

const def = 'https://example.com/openapi.json';

// No definition to read, nobody checks validation: one alert on the instance
const api = new OpenAPIBackend({ definition: def }); // $ Alert
api.register({
  createThing: (c) => c.request.requestBody,
  destructured: ({ request }) => request.query,
  noInput: () => 'pong',
});

// One handler checks c.validation itself: the author knows, stay quiet
const checked = new OpenAPIBackend({ definition: def });
checked.register({
  createThing: (c) => (c.validation.valid ? c.request.requestBody : null),
  other: (c) => c.request.query,
});

const off = new OpenAPIBackend({ definition: def, validate: false });
off.register('createThing', (c) => c.request.requestBody);

const aliased = new OpenAPIBackend({ definition: def, handlers: { 400: () => ({ statusCode: 400 }) } });
aliased.register('createThing', (c) => c.request.requestBody);

const hooked = new OpenAPIBackend({ definition: def });
hooked.register({
  preOperationHandler: (c) => {
    if (c.validation && c.validation.errors) throw new Error('400');
  },
  createThing: (c) => c.request.requestBody,
});

// Handlers that only return static data don't depend on validation
const noInput = new OpenAPIBackend({ definition: def, handlers: { ping: () => 'pong' } });

// A handler we can't see into might check validation
const wrapped = new OpenAPIBackend({ definition: def, handlers: { a: (c) => c.request.body, b: withValidation((c) => c.request.body) } });
