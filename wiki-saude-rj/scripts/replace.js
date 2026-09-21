const { gql } = require('./lib');

(async () => {
  const search = process.argv[2];
  const replace = process.argv[3];
  if (!search || replace === undefined) {
    console.error('Uso: node replace.js <texto> <substituto> [ids...]');
    console.error('Sem ids, verifica todas as páginas. Com ids, verifica somente as páginas indicadas.');
    process.exit(1);
  }
  const ids = process.argv.slice(4).map(Number);
  let pages;
  if (ids.length) {
    pages = ids;
  } else {
    const data = await gql('{ pages { list { id } } }');
    pages = data.pages.list.map(p => p.id);
  }

  let total = 0;
  for (const id of pages) {
    const data = await gql(`{ pages { single(id: ${id}) { content tags { tag } } } }`);
    const p = data.pages.single;
    const occurrences = (p.content.split(search).length - 1);
    if (occurrences === 0) continue;
    const newContent = p.content.split(search).join(replace);
    const tags = p.tags.map(t => t.tag);
    const upd = await gql(`mutation { pages { update(id: ${id}, content: ${JSON.stringify(newContent)}, tags: ${JSON.stringify(tags)}) { responseResult { succeeded errorCode slug message } } } }`);
    const r = upd.pages.update.responseResult;
    if (!r.succeeded) {
      console.error(`página ${id}: FALHOU - ${r.message}`);
      process.exitCode = 1;
      continue;
    }
    console.log(`página ${id}: ${occurrences} ocorrência(s) substituída(s)`);
    total += occurrences;
  }
  console.log(`Total: ${total} ocorrência(s) substituída(s) em ${pages.length} página(s) verificada(s).`);
})();
