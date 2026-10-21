# Clonar projeto a partir do nome

O usuário informa **só o nome** ("clona o siopa"). A skill descobre o caminho completo no GitLab, confirma com o usuário e só então clona.

## Fatos do ambiente (constatados em 2026-10-21)

- `gitlab-prod.saude.rj.gov.br` e `gitlab.saude.rj.gov.br` são **a mesma instância**. O `glab` está autenticado no `-prod` (host da API); a URL de clone que a API devolve usa `gitlab.saude.rj.gov.br` (ssh). `glab` contra `gitlab.saude` dá 401: não é outro servidor.
- `glab repo search` não tem `--hostname`: use `GITLAB_HOST=gitlab-prod.saude.rj.gov.br`.
- Busca por nome devolve vários candidatos (`siopa` → `siopa/siopa` e `siopa-charts`); nenhum resultado devolve `[]`.
- Destino convencional: `~/dev/projects/<nome>` (layout real da máquina; worktrees ao lado, como `sindras-wt-004`). Não usar o layout `~/dev/ses/...` da skill `organizar-projetos`.

## Passo a passo

1. **Localizar:** `bash ~/.config/ai/skills/t3-code-orquestracao/scripts/localizar-repo.sh <nome>`. Saída TSV, match exato primeiro: `path_with_namespace`, `ssh_url`, `destino_proposto`, `destino_existe`, `arquivado`. Ignore candidatos `*-deletion_scheduled-*` a menos que o usuário peça.
2. **Já existe?** Compare com `t3_project_list`: o `repositoryIdentity.canonicalKey` dos projetos é `gitlab.saude.rj.gov.br/<path_with_namespace>` (ou `gitlab-prod...` em remotes https antigos; trate os dois hosts como iguais). Se já está registrado ou o destino existe no disco, diga onde está e pergunte se quer usar o existente.
3. **Confirmar com o usuário** (skill `decisoes-com-usuario`), numa rodada só:
   - Candidato correto? Quando houver mais de um, cada candidato é uma opção, com o match exato primeiro como recomendado.
   - Destino: `~/dev/projects/<nome>` (Recommended) ou outro caminho.
   - Registrar como projeto T3 e abrir thread? (Recommended: registrar; thread só se houver tarefa.)
   Protocolo não se pergunta: o padrão é ssh (o `glab` está configurado assim e o `git ls-remote` ssh funciona).
4. **Checar acesso** sem clonar: `git ls-remote <ssh_url> HEAD`.
5. **Clonar:** `t3_project_clone` com `destinationPath`, `provider: "gitlab"`, `repository: "<path_with_namespace>"`, `protocol: "ssh"` (ou `remoteUrl` direto; os dois funcionam). Destino não vazio → erro `Destination path already exists and is not empty`; a ferramenta não adota nem apaga o destino.
6. **Registrar:** `t3_project_create` com `title: <nome>` e `workspaceRoot: <cwd retornado>`. O `repositoryIdentity` vem `null` na resposta e é preenchido em seguida (`t3_project_read` mostra).
7. **Thread (opcional):** `t3_thread_launch` com `projectId` novo e a tarefa em `message` ([threads.md](threads.md)).
8. **Relatar:** caminho, remote, `projectId` e link da thread, se criada.

## Outros hosts

- Outro GitLab: `GITLAB_HOST=<host> scripts/localizar-repo.sh <nome>` (exige `glab auth login` nesse host; se `glab auth status` não listar o host, avise e pergunte a URL).
- GitHub: `gh search repos <nome> --owner <owner> --json fullName,sshUrl` e o mesmo fluxo a partir do passo 2, com `provider: "github"`.
- URL completa dada pelo usuário: pule o passo 1 e siga do 2.
