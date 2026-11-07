<!-- desc: Regras gerais de uso das skills (quando carregar, não copiar, sem segredo em claro) -->
## Uso das skills

- As skills instaladas nesta máquina ficam no diretório de skills do CLI (ex.: `~/.claude/skills/<nome>`). Cada skill tem um `SKILL.md`; o campo `description` do frontmatter diz quando ela deve ser carregada.
- Antes de agir numa tarefa, confira se alguma skill cobre o pedido pelo `description`, e carregue-a (pela ferramenta de skills do CLI ou lendo o `SKILL.md`) antes de improvisar um procedimento.
- Carregue só o que a tarefa pede. Quando o `SKILL.md` for um roteador, leia apenas o módulo indicado na tabela, não a pasta inteira.
- Skills são a fonte do procedimento: não copie o conteúdo delas para outros arquivos. Se uma skill estiver errada ou incompleta, corrija-a no repositório (`~/.config/ai/skills`) e rode `bin/install.sh` para sincronizar.
- Valores específicos de uma máquina (hosts, nomes de usuário, tokens, caminhos pessoais) não vão para skills compartilhadas. Use marcadores `<...>` ou arquivos de configuração locais.
- Segredos nunca aparecem em texto claro no chat, em arquivo versionado ou em argumento de processo. Use o cofre indicado pela skill `vault-factory`.
