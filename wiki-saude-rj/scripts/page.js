const { gql } = require('./lib');

(async () => {
  const arg = process.argv[2];
  if (!arg) {
    console.error('Uso: node page.js <id|path>');
    process.exit(1);
  }
  const fields = 'id path title description content tags { tag } isPublished isPrivate locale createdAt updatedAt';
  const data = /^\d+$/.test(arg)
    ? await gql(`{ pages { single(id: ${arg}) { ${fields} } } }`)
    : await gql(`{ pages { singleByPath(path: ${JSON.stringify(arg)}, locale: "en") { ${fields} } } }`);
  const result = /^\d+$/.test(arg) ? data.pages.single : data.pages.singleByPath;
  console.log(JSON.stringify(result, null, 2));
})();
