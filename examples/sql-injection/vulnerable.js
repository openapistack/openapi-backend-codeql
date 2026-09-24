// Not an openapi-backend misconfiguration: a plain SQL injection in an operation handler.
// CodeQL's built-in js/sql-injection query can't see it on its own, because openapi-backend
// builds `c.request` inside node_modules. The openapistack/openapi-backend-models pack
// tells CodeQL that `c.request` is user input, and the alert appears.
const { OpenAPIBackend } = require('openapi-backend');
const { Pool } = require('pg');

const db = new Pool();

const api = new OpenAPIBackend({
  definition: './openapi.yml',
  strict: true,
  handlers: {
    getPet: (c) => db.query(`SELECT * FROM pets WHERE id = ${c.request.params.id}`), // $ Alert
  },
});

api.register('findPets', (c) => {
  const { name } = c.request.query; // $ Source
  return db.query(`SELECT * FROM pets WHERE name = '${name}'`); // $ Alert
});

module.exports = api;
