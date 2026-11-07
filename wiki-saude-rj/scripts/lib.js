const fs = require('fs');
const path = require('path');
const os = require('os');
const { execSync } = require('child_process');

const TOKEN_PATH = path.join(os.homedir(), '.claude', 'secrets', 'wiki-saude-rj', 'token');
const OP_REF = 'op://Services IA/Envs kilo Skills/wiki_saude_rj_token';
const ENDPOINT = 'https://wiki.saude.rj.gov.br/graphql';

function fetchFrom1Password() {
  try {
    // Depende da integração de CLI do app desktop do 1Password (biometria/desbloqueio),
    // sem service account — é o mecanismo padrão numa estação de trabalho pessoal.
    const token = execSync(`op read "${OP_REF}"`, { encoding: 'utf8' }).trim();
    if (!token) throw new Error('vazio');
    fs.mkdirSync(path.dirname(TOKEN_PATH), { recursive: true });
    fs.writeFileSync(TOKEN_PATH, token + '\n', { mode: 0o600 });
    return token;
  } catch (e) {
    return null;
  }
}

function loadToken() {
  if (process.env.WIKI_SAUDE_RJ_TOKEN) return process.env.WIKI_SAUDE_RJ_TOKEN;
  try {
    return fs.readFileSync(TOKEN_PATH, 'utf8').trim();
  } catch (e) {
    const token = fetchFrom1Password();
    if (!token) {
      console.error(`Token não encontrado em ${TOKEN_PATH}, na env WIKI_SAUDE_RJ_TOKEN nem no 1Password (${OP_REF}). Verifique o item "Envs kilo Skills".`);
      process.exit(1);
    }
    return token;
  }
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
