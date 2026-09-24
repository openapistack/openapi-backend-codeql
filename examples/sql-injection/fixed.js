const { OpenAPIBackend } = require('openapi-backend');
const { Pool } = require('pg');

const db = new Pool();

// Parameterised queries: the driver escapes the values.
const api = new OpenAPIBackend({
  definition: './openapi.yml',
  strict: true,
  handlers: {
    getPet: (c) => db.query('SELECT * FROM pets WHERE id = $1', [c.request.params.id]),
    findPets: (c) => db.query('SELECT * FROM pets WHERE name = $1', [c.request.query.name]),
  },
});

module.exports = api;
