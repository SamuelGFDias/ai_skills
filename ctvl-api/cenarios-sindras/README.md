# Cenários de validação das regras da feature 004 (cofre CT-VL DEV)

Prova, com dados **sintéticos** (CPF/CNS gerados e válidos, FR-024), as regras de negócio da feature 004 do Sindras (`specs/004-tokenizacao-dados-sensiveis/spec.md` no checkout do Sindras) contra o cofre DEV, antes de implementar no app. Contexto e passo a passo geral: `specs/004-tokenizacao-dados-sensiveis/quickstart.md` (seção 4).

> Este kit é versionado na skill `ctvl-api` (`~/.config/ai/skills/ctvl-api/cenarios-sindras/`), **não** no repositório do Sindras. É específico do sistema `sindras` (templates `SINDRAS_CPF`/`SINDRAS_CNS` no tokengroup `SES`) e só LÊ/tokeniza com dado sintético; escritas de configuração ficam nos subcomandos do `ctvl`.

## Pré-requisitos

- Um checkout do Sindras (para o `config-sindras-dev.yaml` e o `.env.Development`): rode a partir dele ou exporte `SINDRAS_ROOT=<raiz>`.
- `ctvl` no PATH, `python3` com `httpx` e `pytest`.
- `~/dev/sindras/sindras.env` com as seis variáveis `CTVL_SINDRAS_<NOME>_PASSWORD` (SVC_TOKENIZE, TOTAL, CPF_3_LEFT_2_RIGHT, CPF_0_LEFT_2_RIGHT, CNS_3_LEFT, CNS_0_LEFT_0_RIGHT). O `fluxo-dev.sh` carrega com `set -a`. Outro caminho: `SINDRAS_ENV=...`.
- Host, CA e timeout do cofre vêm de `CTVL_HOST`, `CTVL_CA_BUNDLE`, `CTVL_TIMEOUT_SECONDS`, `CTVL_INSECURE_TLS` no ambiente ou no `.env.Development` (procurado em `CTVL_ENV_FILE`, depois em `SINDRAS_ROOT`, no cwd e no `git rev-parse --show-toplevel` do cwd, em `src/Sindras.Infra.CrossCutting/ConfigurationEnvironment/`). Nada disso é impresso.
- Config do `ctvl`: `<raiz>/docs/tokenizacao-ctvl/config-sindras-dev.yaml` (sobrescrevível por `--config ARQ` ou `CTVL_CONFIG`).
- Saída: `$SINDRAS_ROOT/scripts/ctvl-experiments/out/cenarios-<modo>/` se `scripts/ctvl-experiments/` existir; senão `./out/` no cwd. O `.gitignore` do kit ignora `out/`.

## Ordem de execução (cwd = checkout do Sindras)

```bash
K=~/.config/ai/skills/ctvl-api/cenarios-sindras
$K/fluxo-dev.sh plan                      # o que falta no cofre
$K/fluxo-dev.sh apply --yes               # sem --yes só mostra o plano
$K/fluxo-dev.sh verificar                 # verify-mask cpf e cns
$K/fluxo-dev.sh habilitar <usuario> --yes # um por vez, os 4 mascarados
$K/fluxo-dev.sh cenarios --cenario todos
```

Autoteste sem cofre (de qualquer cwd): `$K/fluxo-dev.sh cenarios --offline --cenario todos` (servidor falso `fake_dados.py`) e `python3 -m pytest $K -q`.

Opções do runner: `--cenario C1..C6|todos|C1,C3`, `--amostra N` (50), `--lote N` (1000, teto 5000), `--so-leitura`, `--offline`, `--verbose`.

## O que cada cenário prova

| Cenário | Regras | Prova |
|---|---|---|
| C1 | FR-001, FR-002, FR-004 | DV inválido recusado antes do cofre (0 chamadas); com e sem pontuação gera o mesmo token; token só de dígitos e do tamanho da entrada; determinístico; sem colisão na amostra |
| C2 | FR-005, FR-008 | tokeniza com `sindras_svc_tokenize`; `sindras_total` devolve o original; cada mascarado devolve a máscara esperada (CPF 3+2, CPF 0+2, CNS 3, CNS 0+0, `*`); reporta se a máscara incide sobre os dígitos. SKIP se o mascarado ainda não pode detokenizar |
| C3 | FR-010, FR-011 | lotes de 1, 1000 e 5000; 5156 itens volta objeto e é detectado; lista vazia não é enviada; token inválido falha só o item |
| C4 | FR-015, FR-016 | taxa da falha intermitente de key store, absorvida pelo retry; falha definitiva e tempo esgotado nunca viram dado |
| C5 | FR-023 | template ou grupo trocado nunca devolve o original; `sindras_svc_tokenize` não detokeniza; `sindras_total` não tokeniza |
| C6 | A-03, A-04, P-04 | MEDIÇÃO (sem PASS/FAIL): dígitos em claro no token, entrada mínima aceita, fração de tokens com DV válido, relação de prefixo (StartsWith) |

Limite: o isolamento com credenciais de outro sistema (biae, settorj) não é coberto, só template e grupo trocados.

## Como ler a saída

Uma linha por cenário (`C2  PASS  ...`), sub-linhas só na MEDIÇÃO (C6), rodapé com totais e exit 0 se não houver FAIL. SKIP não reprova (motivo na própria linha). Detalhes **sem dado em claro nem token** (só contagens, formas e categorias de erro) ficam em `out/cenarios-<dev|offline>/<id>.json` (pasta `out/` descrita acima, ignorada pelo git); `--verbose` imprime os detalhes. O motivo cru de erro do cofre nunca é exibido (traz o IP do cliente, FR-021).
