const { gql } = require('./lib');

(async () => {
  const text = process.argv[2];
  if (!text) {
    console.error('Uso: node find.js <texto>');
    process.exit(1);
  }
  const data = await gql('{ pages { list { id path } } }');
  const pages = data.pages.list;
  const hits = [];
  for (const p of pages) {
    const d = await gql(`{ pages { single(id: ${p.id}) { content } } }`);
    const c = d.pages.single.content || '';
    const n = c.split(text).length - 1;
    if (n > 0) hits.push({ id: p.id, path: p.path, occurrences: n });
  }
  console.log(JSON.stringify(hits, null, 1));
})();
