// Testa a ordem de resolução do token em scripts/lib.js: env, arquivo local, depois WIKIJS_TOKEN_REF via vault-read.
// Cada caso roda lib.js num processo filho com HOME e PATH isolados (lib.js resolve o token ao ser importado).
// Nenhum cofre real é tocado e nenhuma requisição de rede é feita. Os tokens são sintéticos.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const LIB = path.join(__dirname, '..', 'scripts', 'lib.js');
const PATH_SEM_VAULT = '/usr/bin:/bin';
const FALLBACK_REL = path.join('.config', 'ai', 'skills', 'vault-factory', 'scripts', 'vault-read.sh');
const REF = 'ref-sintetica:<cofre>/<item>/<campo>';
const TOKEN_ENV = 'token-da-env';
const TOKEN_ARQ = 'token-do-arquivo';
const TOKEN_COFRE = 'token-do-cofre-falso';

// Cria um HOME temporário; com arquivo (mesmo vazio), grava o token local no caminho que a skill usa.
function criarHome(arquivo) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'wikijs-test-'));
  if (arquivo != null) {
    const dir = path.join(home, '.claude', 'secrets', 'wikijs');
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, 'token'), arquivo + '\n', { mode: 0o600 });
  }
  return home;
}

function criarVaultRead(file, corpo) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, '#!/bin/sh\n' + corpo + '\n');
  fs.chmodSync(file, 0o755);
}

// local: 'path' põe o vault-read falso no PATH; 'fallback' põe no caminho da skill vault-factory; null não instala.
// O fake grava o argumento recebido em log, para provar qual referência foi passada.
function cenario({ arquivo, ref, local = null, corpo } = {}) {
  const home = criarHome(arquivo);
  const log = path.join(home, 'vault-read.log');
  const bin = path.join(home, 'bin');
  const corpoPadrao = `printf '%s' "$1" >> '${log}'\nprintf '%s' '${TOKEN_COFRE}'`;
  if (local === 'path') criarVaultRead(path.join(bin, 'vault-read'), corpo ?? corpoPadrao);
  if (local === 'fallback') criarVaultRead(path.join(home, FALLBACK_REL), corpo ?? corpoPadrao);
  const env = { PATH: local === 'path' ? `${bin}:${PATH_SEM_VAULT}` : PATH_SEM_VAULT, HOME: home };
  if (ref) env.WIKIJS_TOKEN_REF = ref;
  return { home, env, log };
}

function rodarLib(env) {
  const r = spawnSync(process.execPath, ['-e', `process.stdout.write(require(${JSON.stringify(LIB)}).TOKEN)`], { env, encoding: 'utf8' });
  return { status: r.status, stdout: r.stdout, stderr: r.stderr };
}

test('env WIKIJS_TOKEN vence arquivo e referência', () => {
  const c = cenario({ arquivo: TOKEN_ARQ, ref: REF, local: 'path' });
  c.env.WIKIJS_TOKEN = TOKEN_ENV;
  const r = rodarLib(c.env);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout, TOKEN_ENV);
  assert.equal(fs.existsSync(c.log), false, 'vault-read não deve ser chamado');
});

test('arquivo local vence WIKIJS_TOKEN_REF', () => {
  const c = cenario({ arquivo: TOKEN_ARQ, ref: REF, local: 'path' });
  const r = rodarLib(c.env);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout, TOKEN_ARQ);
  assert.equal(fs.existsSync(c.log), false, 'vault-read não deve ser chamado');
});

test('arquivo vazio não conta como token e cai para a referência', () => {
  const c = cenario({ arquivo: '', ref: REF, local: 'path' });
  const r = rodarLib(c.env);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout, TOKEN_COFRE);
});

test('WIKIJS_TOKEN_REF usa o vault-read do PATH com a referência exata', () => {
  const c = cenario({ ref: REF, local: 'path' });
  const r = rodarLib(c.env);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout, TOKEN_COFRE);
  assert.equal(fs.readFileSync(c.log, 'utf8'), REF);
});

test('sem vault-read no PATH, cai para o caminho da skill vault-factory', () => {
  const c = cenario({ ref: REF, local: 'fallback' });
  const r = rodarLib(c.env);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout, TOKEN_COFRE);
  assert.equal(fs.readFileSync(c.log, 'utf8'), REF);
});

test('falha do vault-read sai com erro sem vazar o stderr do despachante', () => {
  const corpo = `printf '%s' 'segredo-vazado-no-stderr' >&2\nexit 1`;
  const c = cenario({ ref: REF, local: 'path', corpo });
  const r = rodarLib(c.env);
  assert.equal(r.status, 1);
  assert.equal(r.stdout, '');
  assert.match(r.stderr, /WIKIJS_TOKEN_REF/);
  assert.doesNotMatch(r.stderr, /segredo-vazado-no-stderr/);
});

test('sem nenhuma fonte, a mensagem cita as 3 fontes sem nomes de provider', () => {
  const c = cenario();
  const r = rodarLib(c.env);
  assert.equal(r.status, 1);
  assert.equal(r.stdout, '');
  assert.match(r.stderr, /WIKIJS_TOKEN\b/);
  assert.ok(r.stderr.includes(path.join(c.home, '.claude', 'secrets', 'wikijs', 'token')));
  assert.match(r.stderr, /WIKIJS_TOKEN_REF/);
  assert.match(r.stderr, /vault-factory/);
  assert.doesNotMatch(r.stderr, /1password|gopass|passbolt/i);
});

test('referência definida sem vault-read disponível aponta para a skill vault-factory', () => {
  const c = cenario({ ref: REF });
  const r = rodarLib(c.env);
  assert.equal(r.status, 1);
  assert.equal(r.stdout, '');
  assert.match(r.stderr, /vault-factory/);
});
