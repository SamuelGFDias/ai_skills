const { gql } = require('./lib');

(async () => {
  const term = process.argv[2];
  if (!term) {
    console.error('Uso: node search.js <termo>');
    process.exit(1);
  }
  const data = await gql(`{ pages { search(query: ${JSON.stringify(term)}) { results { id path title description } totalHits } } }`);
  console.log(`Total de resultados: ${data.pages.search.totalHits}`);
  for (const r of data.pages.search.results) {
    console.log(`${r.id}\t${r.path}\t${r.title}`);
  }
})();
