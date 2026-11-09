const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const TOKEN_PATH = path.join(os.homedir(), '.claude', 'secrets', 'wikijs', 'token');
const VAULT_READ_FALLBACK = path.join(os.homedir(), '.config', 'ai', 'skills', 'vault-factory', 'scripts', 'vault-read.sh');
// Base URL da instância Wiki.js, sem barra final (ex.: https://wiki.exemplo.com). Obrigatória.
function endpoint() {
  const base = (process.env.WIKIJS_URL || '').replace(/\/+$/, '');
  if (!base) {
    console.error('WIKIJS_URL não definida: informe a URL base da instância Wiki.js (ex.: https://wiki.exemplo.com).');
    process.exit(1);
  }
  return base + '/graphql';
}

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
  if (process.env.WIKIJS_TOKEN) return process.env.WIKIJS_TOKEN;

  const fromFile = readTokenFile();
  if (fromFile) return fromFile;

  const ref = process.env.WIKIJS_TOKEN_REF;
  if (ref) {
    const fromRef = readVaultRef(ref);
    if (fromRef) return fromRef;
    console.error('WIKIJS_TOKEN_REF está definida, mas o vault-read não entregou o token (ausente ou falha de leitura). Ver a skill vault-factory.');
    process.exit(1);
  }

  console.error(`Token não encontrado: defina a env WIKIJS_TOKEN, grave o token em ${TOKEN_PATH} ou defina WIKIJS_TOKEN_REF com uma referência de cofre (ver a skill vault-factory).`);
  process.exit(1);
}

const TOKEN = loadToken();

async function gql(query, variables) {
  const res = await fetch(endpoint(), {
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

module.exports = { TOKEN, endpoint, gql };
