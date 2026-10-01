---
name: bash-scripting-pitfalls
description: Armadilhas silenciosas de shell scripting em bash — colisão de variáveis ao usar `source` e função com `cond && ação` na última linha sob `set -e` — com exemplos errado/certo e checklist de revisão. Use ao escrever ou revisar script bash que sourceia outros scripts (runner/plugin/setup que exporta variáveis) ou que usa `set -e`/`set -euo pipefail` com funções chamadas como statement solto.
---

# Skill: bash-scripting-pitfalls

**Tipo:** open-source

Duas classes de bug que não geram erro no ponto da causa: o sintoma aparece longe, em outro comando, e só em alguns branches. Aplicar o checklist ao final antes de considerar o script pronto.

## 1. `source` compartilha o namespace inteiro

`source arquivo.sh` roda no mesmo processo: toda variável do filho sobrescreve a do pai, não só as "exportadas". Nomes genéricos (`SCRIPT_DIR`, `TMP`, `OUT`, `i`) colidem com o pai sem aviso, e o erro aparece depois, num comando não relacionado (ex.: glob não expandido, "arquivo não encontrado").

### Regras

- **Prefixar** toda variável local de script sourceado com um namespace único e estável (`<ALVO>_SETUP_...`). Por quê: elimina a colisão na origem.
- **Pai resolve antes do `source`**: calcular e fixar (variável + `cd`, se couber) todo caminho que dependa de suas próprias variáveis *antes* de sourcear. Por quê: se a colisão escapar da revisão, o dano fica contido.
- Só sourcear quando for necessário exportar estado de volta ao pai; caso contrário, executar como subprocesso (`bash filho.sh`).
- Dentro de funções do script sourceado, usar `local` para temporários.

### Exemplo

Errado:

```bash
# run.sh (pai)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/alvo/setup.sh"      # setup.sh também define SCRIPT_DIR e sobrescreve o do pai
run_tests "$SCRIPT_DIR/tests"/*.sh      # caminho agora aponta para o diretório errado

# alvo/setup.sh (filho)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

Certo:

```bash
# run.sh (pai) — resolve o que depende de suas variáveis ANTES do source
RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_GLOB="$RUNNER_DIR/tests"
source "$RUNNER_DIR/alvo/setup.sh"
run_tests "$TESTS_GLOB"/*.sh

# alvo/setup.sh (filho) — namespace único
ALVO_SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

Diagnóstico quando já aconteceu: `bash -x run.sh` e procurar a atribuição que muda o valor da variável após o `source`.

## 2. `set -e` e a última linha de uma função

A exceção do `set -e` para listas `&&`/`||` vale só dentro do escopo atual. Se `cond && ação` é a **última** linha de uma função e `cond` é falsa, a função retorna 1; o caller, que chama a função como statement solto, aborta o script. Passa em testes que só exercitam o primeiro branch (condição verdadeira).

### Regras

- A última linha executável de uma função chamada sob `set -e` não pode ser `cond && ação` nem `cond || ação` quando `cond` é uma **condição de estado** (e falsa não deve ser erro). Converter para `if cond; then ação; fi`, que retorna 0 quando a condição é falsa e não há `else`.
- Rastrear o efeito **lista → função → caller**: o status da lista vira o da função, que vira o do comando simples no call site.
- Se o retorno não-zero for intencional, tratá-lo no call site (`func || true` ou `if func; then`), deixando explícito.
- Testar **cada branch** da condição, não só o caminho feliz.

### Exemplo

Errado:

```bash
set -euo pipefail

sync_for() {
  local cli="$1"
  copiar_arquivos "$cli"
  [[ "$cli" == "alfa" ]] && ALFA_SINCRONIZADO=1   # cond falsa => função retorna 1
}

for cli in alfa beta; do
  sync_for "$cli"          # com "beta" o script inteiro aborta aqui
done
```

Certo:

```bash
sync_for() {
  local cli="$1"
  copiar_arquivos "$cli"
  if [[ "$cli" == "alfa" ]]; then
    ALFA_SINCRONIZADO=1
  fi
}
```

Diagnóstico: `bash -x`, comparando a chamada isolada de cada subcomando (retorna 0 fora do loop) com a execução completa.

## Checklist de revisão

- [ ] Algum script é sourceado? As variáveis do filho têm prefixo único e nenhuma coincide com variável do pai?
- [ ] O pai calcula/fixa seus caminhos antes do `source`?
- [ ] O `source` é mesmo necessário (exportar estado) ou um subprocesso bastaria?
- [ ] Sob `set -e`: cada função termina em comando que retorna 0 em todos os branches, sem `&&`/`||` de condição de estado na última linha?
- [ ] Os retornos não-zero intencionais estão tratados no call site?
- [ ] Foram executados todos os branches (inclusive o da condição falsa), e não só o primeiro argumento/caminho feliz?
- [ ] Rodou o script completo com `bash -x` ao menos uma vez?
