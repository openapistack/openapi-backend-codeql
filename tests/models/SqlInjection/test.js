const { OpenAPIBackend } = require('openapi-backend');
const OpenAPIBackendDefault = require('openapi-backend').default;
const { Pool } = require('pg');

const db = new Pool();

const api = new OpenAPIBackend({
  definition: './openapi.yml',
  handlers: {
    getPet: (c) => db.query(`SELECT * FROM pets WHERE id = ${c.request.params.id}`), // $ Alert
    getPetSafe: (c) => db.query('SELECT * FROM pets WHERE id = $1', [c.request.params.id]),
  },
});

api.register('findPets', async (c) => {
  const { name } = c.request.query; // $ Source
  return db.query(`SELECT * FROM pets WHERE name = '${name}'`); // $ Alert
});

api.register({
  createPet: (c) => db.query(`INSERT INTO pets (name) VALUES ('${c.request.requestBody.name}')`), // $ Alert
});

api.registerSecurityHandler('apiKey', (c) =>
  db.query(`SELECT * FROM keys WHERE key = '${c.request.headers['x-api-key']}'`), // $ Alert
);

const main = async () => {
  const initialized = await new OpenAPIBackendDefault({ definition: './openapi.yml' }).init();
  initialized.register('deletePet', (c) => db.query(`DELETE FROM pets WHERE id = ${c.request.params.id}`)); // $ Alert
};

main();
