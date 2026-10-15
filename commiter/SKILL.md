---
name: commiter
description: Workflow genérico de commit + push de mudanças em repositórios git, com pré-checagens, staging por caminho, mensagem de commit por convenção do repo (sem rodapé de atribuição de IA) e push seguro com rebase em caso de rejeição. Use quando o usuário pedir para commitar, subir o branch, preparar o trabalho para merge, ou antes de usar ferramentas de MR/auto-merge (ex: gitlab-auto-merge).
---

# Skill: commiter

**Tipo:** internal

## Quando executar

- Pedidos para commitar e/ou pushar alterações ("commita isso", "sobe o branch").
- Preparar o trabalho para MR/merge (o passo final de abertura do MR é da ferramenta do repo —
  ver "Encaminhamento").
- Qualquer tarefa que produza mudanças que precisam ir para o remoto.

## Fluxo

### 0. Convenção de nome de branch (GitLab SES)

O padrão aprovado para nome de branch no GitLab SES-RJ **não usa barra (`/`)** — usar hífen no
lugar. Ex.: `fix/correcao` vira `fix-correcao`. Aplicar essa convenção ao criar a branch, antes do
commit e do push.

### 1. Pré-checagens (nunca pular)

```bash
git status --short          # working tree: o que está mudado
git diff --stat             # dimensão das mudanças
git branch --show-current   # branch atual
git log --oneline -3        # contexto do histórico
git rev-list --left-right --count origin/<branch>...HEAD   # divergência local/remota (left=remoto, right=local)
git worktree list           # se a branch estiver em outra worktree, usar `git -C <worktree>`
```

Se a branch já estiver em checkout em outra worktree, **não** fazer checkout — operar com `git -C <worktree>`.

### 2. Staging por caminho (nunca `git add .` cego)

Adicionar apenas os arquivos relevantes à mudança:

```bash
git add caminho/do/arquivo.ts caminho/do/outro.cs
git status                  # conferir o que ficou staged
git diff --cached --stat    # revisar o que vai no commit
```

### 3. Mensagem de commit

- Seguir a convenção do repositório (consultar `git log --oneline` e o `AGENTS.md`/README do projeto).
- Mensagem concisa, descrevendo o **o quê e o porquê**, não o como.
- **Nunca** adicionar rodapé de atribuição de IA (`Co-Authored-By: ...`) nem linha de coautoria.
  A mensagem termina no corpo escrito.
- Se o repo usa conventional commits (`feat:`, `fix:`, `refactor:`...), usar; senão, seguir o padrão local.
- **Se o commit implementa/corrige uma issue rastreada (GitLab ou GitHub), referenciar no corpo
  com a palavra-chave de fechamento correta, não apenas `Refs`/`Ref`.** `Refs #N` só cria um link —
  não fecha a issue. Para o merge da MR/PR executar o fechamento automático, usar uma das palavras
  reconhecidas pela plataforma antes do número: `Closes #N`, `Fixes #N` ou `Resolves #N` (mesmas
  palavras em GitLab e GitHub). Colocar isso no corpo do **commit** (não só na descrição da MR/PR) —
  GitLab também escaneia mensagens de commit ao mergear, então a ação de fechamento sobrevive mesmo
  que a descrição da MR use `Refs` por engano ou seja editada depois. Confirmar antes se o commit
  de fato encerra a issue (se só avança parcialmente, `Refs #N` é o correto e a issue permanece aberta).

```bash
git commit -m "feat: descrição concisa da mudança

Closes #42"
```

### 4. Push seguro

```bash
git push -u origin <branch>   # -u apenas se ainda não houver upstream
```

Se o push for rejeitado (non-fast-forward), rebasear sobre o remoto e reenviar — **nunca forçar push
em branch compartilhada**:

```bash
git pull --rebase origin <branch>
git push
```

Após rebase com conflito: resolver, `git add <arquivos>`, `git rebase --continue`, reenviar.

### 5. Verificação pós-push

```bash
git status                    # árvore limpa
git log --oneline -1          # commit no topo
git rev-parse --abbrev-ref --symbolic-full-name @{u}   # upstream configurado
```

## Encaminhamento

- Repo SES-RJ que usa o script `gitlab-auto-merge`: apontar para `providers/gitlab/automerge.md`
  (a ferramenta faz o push restante + MR + aprovação + auto-merge — não duplicar isso aqui).
- Abertura de issues/milestones: skill `issue-factory` + `providers/gitlab/arquivos.md`.
- Outros hosts: fluxo genérico de MR do próprio repo.

## Cuidados

- **Nunca commitar secrets/credenciais.** Conferir o diff staged antes do commit.
- Não commitar arquivos de build/artefatos a menos que o repo os versione.
- Trabalho não solicitado no commit (ex.: arquivos alterados fora da mudança) — investigar antes de
  incluir; se for de outro contexto, deixar fora e avisar o usuário.
- Ação de push/merge continua exigindo confirmação do usuário quando o fluxo do projeto assim exigir.
