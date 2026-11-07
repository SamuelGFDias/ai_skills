# Fundamentos: CLAUDE.md

Pesquisado em 2026-11-07 nas páginas da Anthropic listadas no fim. Base da skill `claude-md`. A parte sobre hooks está em `claude-guard-hooks/docs/fundamentos.md`.

- **Tamanho:** menos de 200 linhas por arquivo. Arquivo longo consome mais contexto e reduz a aderência.
- **O que entra:** fatos que o Claude precisa ter em toda sessão, como comandos de build e verificação, convenções e regras de "sempre faça X". Também lugares onde o código engana, decisões que não estão no repo, e tudo o que já foi preciso corrigir duas vezes.
- **O que não entra:** o que o Claude acha lendo o repo, como layout de diretórios, lista de dependências e visão de arquitetura.
- **Usuário ou projeto:** `~/.claude/CLAUDE.md` guarda preferências pessoais para todos os projetos. O `CLAUDE.md` do projeto é compartilhado pelo time via git. `CLAUDE.local.md` é pessoal por projeto e fica no `.gitignore`. Todos são concatenados, e não se sobrescrevem.
- **Para onde mover:**
  - procedimento (deploy, checklist, fluxo de uma ferramenta) vai para skill;
  - "toda vez que X, faça Y" vai para hook;
  - restrição de um conjunto de arquivos vai para rule com `paths:`.
  - `@import` organiza, mas não reduz o custo de contexto: o arquivo importado carrega junto.
- **Formato:** cabeçalhos e bullets, instruções concretas e verificáveis, e o porquê das restrições. Acumular ênfase (IMPORTANT, maiúsculas) tende a fazer o Claude aplicar a regra demais. Os modelos atuais seguem uma linha escrita de forma direta. Comentário HTML de bloco é removido antes de entrar no contexto.
- **Manutenção:** ter um dono e revisar mudanças como código. Acrescentar quando o mesmo erro acontece pela segunda vez, e remover periodicamente o que ficou desatualizado. `/doctor` sugere cortes e `/context all` mostra o que foi carregado.

## Fontes

- https://claude.com/resources/articles/steering-claude-code-skills-hooks-rules-subagents-and-more
- https://code.claude.com/docs/en/best-practices
- https://code.claude.com/docs/en/memory
- https://code.claude.com/docs/en/hooks-guide
- https://code.claude.com/docs/en/hooks
