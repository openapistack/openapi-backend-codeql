import OpenAPIBackend, { Context } from 'openapi-backend';

const getOwner = async (c: Context) => ({ id: c.request.params.id });

export const api = new OpenAPIBackend({ // $ Alert
  definition: 'https://example.com/openapi.json',
  securityHandlers: { jwt: async (c: Context) => c.request.headers.authorization === 'Bearer x' },
  handlers: { getOwner },
});
