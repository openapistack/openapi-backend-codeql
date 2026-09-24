import path from 'path';
import OpenAPIBackend from 'openapi-backend';

// JSON spec found through path.join(__dirname, ...).
// listPets allows anonymous access ({}), getPet has no security at all.
const api = new OpenAPIBackend({
  definition: path.join(__dirname, 'specs', 'petstore.json'),
  securityHandlers: { apiKey: (c) => c.request.headers['x-api-key'] === 'secret' },
});

api.register('listPets', (c) => []);
api.register('getPet', (c) => ({}));
api.register('createPet', (c) => ({})); // $ Alert
