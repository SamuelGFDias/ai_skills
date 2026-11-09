const { gql } = require('./lib');

(async () => {
  const data = await gql('{ pages { list { id path title locale isPublished isPrivate createdAt updatedAt } } }');
  for (const p of data.pages.list) {
    const status = p.isPublished ? 'pub' : 'draft';
    console.log(`${p.id}\t${status}\t${p.path}`);
  }
})();
