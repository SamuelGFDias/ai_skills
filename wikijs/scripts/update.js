const fs = require('fs');
const { gql } = require('./lib');

function arg(name) {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

(async () => {
  const id = process.argv[2];
  if (!id) {
    console.error('Uso: node update.js <id> [--content <texto>] [--content-file <arquivo>] [--title <titulo>] [--published true|false] [--tags <json>]');
    process.exit(1);
  }
  const cur = await gql(`{ pages { single(id: ${id}) { title content tags { tag } isPublished } } }`);
  const p = cur.pages.single;

  const content = arg('--content') !== undefined
    ? arg('--content')
    : (arg('--content-file') !== undefined ? fs.readFileSync(arg('--content-file'), 'utf8') : p.content);
  const tags = arg('--tags') !== undefined ? JSON.parse(arg('--tags')) : p.tags.map(t => t.tag);

  const fields = { content, tags };
  if (arg('--title') !== undefined) fields.title = arg('--title');
  if (arg('--published') !== undefined) fields.isPublished = arg('--published') === 'true';

  const parts = Object.entries(fields)
    .map(([k, v]) => `${k}: ${JSON.stringify(v)}`)
    .join(', ');

  const data = await gql(`mutation { pages { update(id: ${id}, ${parts}) { responseResult { succeeded errorCode slug message } } } }`);
  const r = data.pages.update.responseResult;
  console.log(r.succeeded ? `OK: página ${id} atualizada` : `FALHOU: ${r.message}`);
  process.exit(r.succeeded ? 0 : 1);
})();
