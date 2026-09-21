const fs = require('fs');
const { gql } = require('./lib');

(async () => {
  const arg = process.argv[2];
  if (!arg) {
    console.error('Uso: node gql.js "<query>" | node gql.js <arquivo.graphql>');
    process.exit(1);
  }
  const query = fs.existsSync(arg) ? fs.readFileSync(arg, 'utf8') : arg;
  const data = await gql(query);
  console.log(JSON.stringify(data, null, 2));
})();
