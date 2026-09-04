#!/usr/bin/env bun
// Apaga sessões/observações/resumos/prompts de um ou mais "projetos" do claude-mem.
// Uso:
//   bun clear-project.js <projeto> [projeto2 ...]           # dry-run (só mostra contagens)
//   bun clear-project.js --yes <projeto> [projeto2 ...]     # apaga de verdade
//
// "projeto" é o valor da coluna sdk_sessions.project — normalmente o basename do cwd,
// ou o basename do toplevel do git se o cwd for um repositório (ver SKILL.md, seção
// "Como o claude-mem nomeia um projeto"). Rode com dry-run primeiro para conferir que
// o nome não colide com outro projeto antes de usar --yes.
//
// Usa bun:sqlite (não o `sqlite3` do sistema) porque a tabela `observations` tem
// triggers que sincronizam uma tabela virtual FTS5 (`observations_fts`) — o binário
// `sqlite3` do SO costuma faltar o módulo fts5 e falha com "no such module: fts5".

const { Database } = require("bun:sqlite");
const fs = require("fs");
const path = require("path");
const os = require("os");

const dataDir = process.env.CLAUDE_MEM_DATA_DIR || path.join(os.homedir(), ".claude-mem");
const dbPath = path.join(dataDir, "claude-mem.db");

const args = process.argv.slice(2);
const apply = args.includes("--yes");
const projects = args.filter((a) => a !== "--yes");

if (projects.length === 0) {
  console.error("Uso: bun clear-project.js [--yes] <projeto> [projeto2 ...]");
  process.exit(1);
}

const db = new Database(dbPath);
db.run("PRAGMA foreign_keys = ON;");

const placeholders = projects.map(() => "?").join(",");

function counts() {
  return {
    sdk_sessions: db.query(`SELECT COUNT(*) c FROM sdk_sessions WHERE project IN (${placeholders})`).get(...projects).c,
    observations: db.query(`SELECT COUNT(*) c FROM observations WHERE project IN (${placeholders})`).get(...projects).c,
    session_summaries: db.query(`SELECT COUNT(*) c FROM session_summaries WHERE project IN (${placeholders})`).get(...projects).c,
  };
}

console.log("Projetos:", projects.join(", "));
console.log("Antes:", JSON.stringify(counts()));

if (!apply) {
  console.log("\nDry-run (nada foi apagado). Rode de novo com --yes para apagar.");
  db.close();
  process.exit(0);
}

const backupDir = path.join(dataDir, "backups");
fs.mkdirSync(backupDir, { recursive: true });
const stamp = new Date().toISOString().replace(/[:.]/g, "-");
const backupPath = path.join(backupDir, `claude-mem-before-clear-${projects.join("_")}-${stamp}.db`);
fs.copyFileSync(dbPath, backupPath);
console.log("Backup:", backupPath);

const before = db.query(`SELECT COUNT(*) c FROM user_prompts WHERE session_db_id NOT IN (SELECT id FROM sdk_sessions)`).get().c;

db.query(`DELETE FROM sdk_sessions WHERE project IN (${placeholders})`).run(...projects);

const after = db.query(`SELECT COUNT(*) c FROM user_prompts WHERE session_db_id NOT IN (SELECT id FROM sdk_sessions)`).get().c;
if (after > before) {
  console.warn(
    `Aviso: user_prompts orfaos subiu de ${before} para ${after}. ` +
      `Isso pode ser um problema pre-existente (confira o backup) ou uma falha de cascade.`
  );
}

console.log("Depois:", JSON.stringify(counts()));
db.run("VACUUM;");
db.close();
console.log("OK");
