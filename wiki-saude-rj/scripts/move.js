const { gql } = require('./lib');

(async () => {
  const id = process.argv[2];
  const dest = process.argv[3];
  if (!id || !dest) {
    console.error('Uso: node move.js <id> <destinationPath>');
    process.exit(1);
  }
  const data = await gql(`mutation { pages { move(id: ${id}, destinationPath: ${JSON.stringify(dest)}, destinationLocale: "en") { responseResult { succeeded errorCode slug message } } } }`);
  const r = data.pages.move.responseResult;
  console.log(r.succeeded ? `OK: página ${id} movida para ${dest}` : `FALHOU: ${r.message}`);
  process.exit(r.succeeded ? 0 : 1);
})();
