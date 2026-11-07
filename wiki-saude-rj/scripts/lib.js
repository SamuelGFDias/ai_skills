const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const TOKEN_PATH = path.join(os.homedir(), '.claude', 'secrets', 'wiki-saude-rj', 'token');
const VAULT_READ_FALLBACK = path.join(os.homedir(), '.config', 'ai', 'skills', 'vault-factory', 'scripts', 'vault-read.sh');
const ENDPOINT = 'https://wiki.saude.rj.gov.br/graphql';

// Lê a referência pelo despachante vault-read (contrato em vault-factory/docs/contrato-provider.md).
// execFileSync não usa shell; o stderr é descartado e o token nunca vai para mensagem de erro.
function readVaultRef(ref) {
  for (const bin of ['vault-read', VAULT_READ_FALLBACK]) {
    try {
      return execFileSync(bin, [ref], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim() || null;
    } catch (e) {
      if (e.code !== 'ENOENT') return null;
    }
  }
  return null;
}

function readTokenFile() {
  try {
    return fs.readFileSync(TOKEN_PATH, 'utf8').trim() || null;
  } catch (e) {
    return null;
  }
}

function loadToken() {
  if (process.env.WIKI_SAUDE_RJ_TOKEN) return process.env.WIKI_SAUDE_RJ_TOKEN;

  const fromFile = readTokenFile();
  if (fromFile) return fromFile;

  const ref = process.env.WIKI_SAUDE_RJ_TOKEN_REF;
  if (ref) {
    const fromRef = readVaultRef(ref);
    if (fromRef) return fromRef;
    console.error('WIKI_SAUDE_RJ_TOKEN_REF está definida, mas o vault-read não entregou o token (ausente ou falha de leitura). Ver a skill vault-factory.');
    process.exit(1);
  }

  console.error(`Token não encontrado: defina a env WIKI_SAUDE_RJ_TOKEN, grave o token em ${TOKEN_PATH} ou defina WIKI_SAUDE_RJ_TOKEN_REF com uma referência de cofre (ver a skill vault-factory).`);
  process.exit(1);
}

const TOKEN = loadToken();

async function gql(query, variables) {
  const res = await fetch(ENDPOINT, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + TOKEN },
    body: JSON.stringify({ query, variables })
  });
  const json = await res.json();
  if (json.errors) {
    const msgs = json.errors.map(e => (e.message || JSON.stringify(e))).join('; ');
    throw new Error('GraphQL error: ' + msgs);
  }
  return json.data;
}

module.exports = { TOKEN, ENDPOINT, gql };
