---
name: claude-md
description: Cria, audita e enxuga arquivos CLAUDE.md (do usuário, do projeto e CLAUDE.local.md) seguindo as recomendações da Anthropic — menos de 200 linhas, só o que o Claude não acha lendo o repo, procedimento movido para skill, regra que precisa valer sempre movida para hook, restrição de arquivos movida para rule com paths. Use ao criar o CLAUDE.md de um projeto, quando ele passar de 200 linhas, quando o Claude ignorar uma instrução que está nele, ou para revisar periodicamente o ~/.claude/CLAUDE.md.
---

# Skill: claude-md

**Tipo:** internal

## Quando executar

- Ao criar o CLAUDE.md de um projeto, ou ao gerar um com `/init` e precisar podá-lo.
- Quando um CLAUDE.md passar de 200 linhas, ou o Claude Code avisar no início da sessão que ele está grande.
- Quando o Claude errar duas vezes a mesma coisa, ou ignorar uma linha que já está no CLAUDE.md.
- Na revisão periódica do `~/.claude/CLAUDE.md`.

Fundamentos e fontes: `docs/fundamentos.md`.

## Princípios

1. **Menos de 200 linhas por arquivo.** Arquivo longo consome contexto em toda sessão e reduz a aderência às instruções.
2. **Só o que o Claude não acha sozinho.** Teste de cada linha: "ele acharia isto lendo o código?" e "ele iria mesmo procurar?". Se as duas respostas forem sim, a linha sai.
3. **CLAUDE.md é contexto, não imposição.** O modelo pode não seguir. O que precisa valer sempre vai para hook.
4. **Linha direta, sem ênfase acumulada.** IMPORTANT e MAIÚSCULAS tendem a fazer o Claude aplicar a regra em excesso. Se uma linha escrita de forma direta é ignorada, a solução é hook ou regra de deny, não mais ênfase.
5. **Concreto e verificável.** Prefira "use indentação de 2 espaços" a "formate bem o código", e diga o porquê das restrições.

## Para onde vai cada tipo de conteúdo

| conteúdo | destino |
|---|---|
| fato necessário em toda sessão: comando de build ou teste, convenção, "sempre faça X" | CLAUDE.md |
| armadilha onde o código engana, decisão que não está no repo, erro já corrigido duas vezes | CLAUDE.md |
| procedimento: deploy, checklist, fluxo de uma ferramenta ou equipamento | skill |
| "toda vez que X, faça Y", ou regra que não pode falhar | hook (veja `claude-guard-hooks`) |
| restrição de um conjunto de arquivos | rule em `.claude/rules/` com `paths:` |
| preferência pessoal num projeto compartilhado | `CLAUDE.local.md`, no `.gitignore` |
| preferência pessoal para todos os projetos | `~/.claude/CLAUDE.md` |
| layout de diretórios, lista de dependências, visão de arquitetura | nada: o Claude lê do repo |
| segredo, senha, token | nunca. Vault (`vault-factory`) ou variável de ambiente |

`@import` organiza um arquivo longo, mas não reduz o custo: o arquivo importado é carregado junto. Para cortar contexto, mova o conteúdo para uma skill, que só carrega quando é usada.

## Níveis

- `~/.claude/CLAUDE.md`: pessoal, vale em todos os projetos. Deve ser o mais curto dos três, porque é carregado em toda sessão de qualquer repositório. Conteúdo de um único domínio (um equipamento, um cliente, um projeto) não pertence aqui: vai para uma skill.
- `./CLAUDE.md` ou `./.claude/CLAUDE.md`: do projeto, compartilhado pelo time via git.
- `./CLAUDE.local.md`: pessoal naquele projeto, fora do git.
- Todos são concatenados, do mais amplo para o mais específico, e não se sobrescrevem. Instrução contraditória entre níveis é defeito a corrigir.

## Procedimento de auditoria

1. **Medir:** `wc -l` de cada CLAUDE.md envolvido, e listar o que já existe em skills, hooks (`settings.json`) e rules, para não duplicar.
2. **Classificar cada bloco** pela tabela acima: `manter`, `skill`, `hook`, `rule`, `local` ou `remover`, com uma frase de motivo. Mostrar a tabela ao usuário antes de mudar qualquer arquivo.
3. **Preservar antes de mover:** o conteúdo que vai para uma skill entra na skill primeiro. Se a skill já existe, mesclar e eliminar duplicata, mantendo a versão mais recente do fato. Só depois o bloco sai do CLAUDE.md. Nada se perde no caminho.
4. **Backup:** copiar o CLAUDE.md original para um arquivo com data antes de reescrevê-lo.
5. **Reescrever** o que fica, com cabeçalhos e bullets. Onde um bloco saiu para uma skill, deixar no máximo um ponteiro de uma linha, e só se o nome e a descrição da skill não bastarem para ela ser acionada.
6. **Verificar:** menos de 200 linhas; nenhuma informação sumiu (cada bloco removido tem destino ou motivo de remoção); nenhum segredo; nenhum caminho ou comando citado que não exista. Na próxima sessão, `/context all` mostra o que foi carregado e `/doctor` sugere mais cortes.

## Criar o CLAUDE.md de um projeto

1. Rodar `/init` ou a skill `codebase-onboarding` para ter um ponto de partida. O trabalho daí em diante é sobretudo remover linhas.
2. Manter: como fazer build, testar e rodar; convenções que o código não deixa óbvias; armadilhas conhecidas; decisões tomadas fora do repo.
3. Remover: o que descreve a estrutura, que o Claude lê sozinho.
4. Se o projeto tiver `AGENTS.md`, preferir manter as instruções nele e deixar o CLAUDE.md com uma linha que o importe (`@AGENTS.md`), para servir também a outros CLIs.

## Manutenção

- Acrescentar uma linha quando o mesmo erro acontecer pela segunda vez.
- Revisar periodicamente e remover o que ficou desatualizado ou contraditório.
- O CLAUDE.md de projeto tem dono e é revisado como código.
