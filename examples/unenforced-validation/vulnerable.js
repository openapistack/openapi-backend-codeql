// The schema says `role` can only be "user" and `name` is at most 64 characters.
// Without a validationFail handler, a body that breaks those rules still reaches createUser:
// { "role": "admin", "name": "AAAA...1MB" } goes straight into the database.
const { OpenAPIBackend } = require('openapi-backend');
const { users } = require('./app');

const api = new OpenAPIBackend({ definition: './openapi.yml' });

api.register({
  listUsers: () => users.list(), // takes no input, so not flagged
  createUser: (c) => users.insert(c.request.requestBody), // $ Alert
});

module.exports = api;
