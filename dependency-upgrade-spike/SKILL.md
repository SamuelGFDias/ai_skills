---
name: dependency-upgrade-spike
description: Roteiro para decidir sobre upgrade/bump de dependência (versão major ou com breaking changes suspeitas) sem depender de changelog/release notes como fonte de verdade. Use na fase de pesquisa (Phase 0) de um plano spec-driven que envolva mudar versão de uma lib, ou sempre que uma decisão técnica for justificada por "o changelog diz que...".
---

# Skill: dependency-upgrade-spike

**Tipo:** internal

## Quando executar

Sempre que uma tarefa de pesquisa (spike) precisar decidir se um upgrade de dependência é seguro, ou
quando um plano/gate técnico depender de um comportamento específico da versão nova (um assert, um
erro, uma garantia de tipo). Vale tanto dentro da Phase 0 de um workflow `speckit` quanto fora dele.

## Por que não confiar só no changelog

Changelog e release notes documentam o que o autor **lembrou** de registrar como breaking change.
Não documentam: funções removidas sem aviso, mudanças de assinatura que só quebram inferência de
tipo, reordenação de parâmetros de construtor, ou uma checagem que migrou de runtime para
compile-time (o que muda a *classe* do erro, não só o texto dele). Uma decisão de migração baseada em
changelog é **hipótese**, não verificação — a fonte de verdade é o código-fonte da versão-alvo
confrontado com os símbolos que o projeto realmente usa, disponível localmente e barato de checar.

## Roteiro

1. **Listar os símbolos efetivamente usados.** Grep no próprio projeto pelos símbolos (funções,
   tipos, construtores, macros) importados da dependência — não pelo que a documentação da lib expõe,
   e sim pelo que o projeto de fato chama.
2. **Baixar a versão-alvo e ler o código-fonte real.** A maioria dos gerenciadores de pacote já
   baixa/cacheia o source da dependência localmente (ex.: `~/.cargo/registry/src/`,
   `node_modules/`, pacote NuGet extraído). Conferir cada símbolo listado no passo 1 contra a
   assinatura real na versão nova — não contra a doc, não contra o changelog.
3. **Se o plano/gate depender de um comportamento específico da versão nova** (um `assert` que passa
   a falhar, um erro que passa a ser pego, uma garantia de tipo nova), confirmar esse comportamento
   lendo o trecho de código-fonte responsável por ele — não assumir a partir da descrição em prosa do
   release notes. Um mecanismo pode ter sido reimplementado de um jeito que muda a natureza do
   comportamento (ex.: uma checagem que era `debug_assert!` em runtime virou um bloco `const {}` em
   compile-time — a classe do erro inteira mudou, de falha em runtime para falha de build).
4. **Só então estimar esforço e risco.** Com os símbolos confirmados e o comportamento-gate
   verificado no código, o esforço estimado reflete o que vai realmente acontecer na migração, não o
   que o changelog deu a entender.

## Armadilha

Tratar "as breaking changes confirmadas não atingem este crate/pacote" como conclusão de pesquisa
quando essa frase veio só da leitura do changelog. Rodar o roteiro acima primeiro; só registrar a
conclusão de baixo risco depois de ter confrontado os símbolos usados contra o código-fonte da versão
nova.

## Integração com speckit

Numa Phase 0 (`research.md`) de um workflow `speckit` que envolva bump de dependência, este roteiro
substitui "ler changelog/release notes" como método de pesquisa. O `research.md` deve registrar, por
símbolo checado, a linha do código-fonte da versão-alvo que confirma a assinatura/comportamento — não
uma citação do changelog.
