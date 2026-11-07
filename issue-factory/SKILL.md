---
name: issue-factory
description: Workflow genérico de gestão de issues (criar, comentar solução, fechar, milestones, datas, padrão de título) independente da plataforma. Os comandos concretos da plataforma ficam em providers/ — GitLab em providers/gitlab/arquivos.md e GitHub em providers/github/arquivos.md. Use quando o usuário pedir para abrir, atualizar ou fechar issues em um tracker de tarefas.
---

# Skill: issue-factory

**Tipo:** internal

## Quando executar

Quando houver demandas de desenvolvimento descritas pelo usuário que precisem ser abertas,
atualizadas ou fechadas como issues no tracker de tarefas do projeto. **Não há atas de reunião ou
arquivos `.md` pré-criados** — as demandas são descritas diretamente na conversa.

## Providers

Os comandos concretos (host, auth, projeto, labels, milestones, GraphQL) estão em:

- **GitLab SES-RJ** → `providers/gitlab/arquivos.md` (ler antes de executar comandos `glab`).
- **GitHub** → `providers/github/arquivos.md` (ler antes de executar comandos `gh`).

Ao adaptar para outro tracker, manter este fluxo e trocar apenas a seção do provider.

## Coleta de informações interativas

Antes de criar a issue, **pergunte ao usuário** cada item abaixo, **a menos que já tenham sido
informados via prompt**:

| Item | Perguntar? | Padrão |
|------|-----------|--------|
| **Usuário** (assignee) | Sempre, salvo se já passado | — |
| **Milestone** | Sempre, salvo se já passado | — |
| **Projeto** | Sempre, salvo se já passado | o do grupo/contexto |
| **Label de status** (ex: Backlog, In progress) | Sempre, salvo se já passado | — |
| **Label do projeto** | Sempre, salvo se já passado | — |

Onde cada label/milestone vive é definido pelo provider (ver `providers/github/arquivos.md`).

## Estrutura esperada de cada issue

1. **Título** — descrição objetiva (ver padrão abaixo)
2. **US (História de Usuário)** — "Como [papel], quero [funcionalidade], para [benefício]"
3. **Descrição da solução** — implementação, arquivos alterados, commits relacionados

Cada demanda deve conter: **Título** (curto e objetivo), **US** (quem, o que, por quê) e **Solução**
(descrição técnica, arquivos alterados, commits relacionados).

## Padrão de título de issue

O título da issue **não é** mensagem de commit. Formato:

```
<Módulo/Escopo> - <Ação no infinitivo> <complemento>
```

- **`<Módulo/Escopo>`**: a tela, entidade, componente ou área do sistema afetada (ex: `Recepção`,
  `Tabela Recepção`, `Editar dados pessoais`, `Migrations`, `Testes`, `Build`, `Agenda`). Deve ser o
  que a pessoa reconhece de imediato ao escanear a lista.
- **Separador**: ` - ` (espaço-hífen-espaço).
- **`<Ação>`**: verbo no infinitivo (ex: `Corrigir`, `Adicionar`, `Padronizar`, `Validar`,
  `Permitir`, `Remover`, `Investigar`, `Ajustar`, `Configurar`, `Incluir`).
- Primeira letra maiúscula em cada parte, resto em minúsculas — exceto nomes próprios, siglas e
  identificadores de código.
- **Proibido** prefixo de conventional commits (`feat:`, `fix:`, `refactor:`...) — esses rótulos
  pertencem à mensagem de commit/PR, não ao título.
- Sem emojis no título; sem sufixos técnicos entre parênteses (ex: `(no-op)`).
- Título autoexplicativo por si só, sem precisar abrir a issue.

Exceção tolerada: prefixo entre colchetes com código de requisito (ex: `[RF-14]`, `[Melhoria]`,
`[Correção]`) pode vir **antes** do módulo, quando já for convenção do projeto — mas nunca substituir
o formato `Módulo - Ação`, nem misturar com prefixo de conventional commit.

**Exemplos (antes → depois):**
- `refactor: adicionar IDesignTimeDbContextFactory para gerar migrations sem as ~34 variáveis de ambiente`
  → `Migrations - Adicionar IDesignTimeDbContextFactory para gerar sem exigir variáveis de ambiente de runtime`
- `test: RollForward ausente em Talonario.Api.Tests e Infra.CrossCutting.Tests impede rodar a suíte local`
  → `Testes - Configurar RollForward em Talonario.Api.Tests e Infra.CrossCutting.Tests para rodar a suíte localmente`
- `build: build da solução dispara o npm build e apaga o wwwroot da Api`
  → `Build - Corrigir build da solução para não disparar o build do Angular e apagar o wwwroot da Api`
- `refactor: validação de duplicidade de período em ExisteAgendaData nunca dispara (no-op)`
  → `Agenda - Corrigir validação de duplicidade de período em ExisteAgendaData que nunca dispara`

Sempre validar o título contra este padrão antes de submeter.

## Fluxo — Criar Issue

1. Verificar autenticação na plataforma (provider).
2. **Verificar se já existe issue aberta sobre o assunto** antes de criar — a busca de duplicata é
   **obrigatória, nunca pulável** (comando definido pelo provider). Buscar nos campos de título
   e descrição usando termos-chave da demanda. Se houver correspondência clara (mesmo escopo, aberta
   e ativa), **não criar duplicata**: reportar ao usuário a issue existente (número, título, link) e
   deixar que ele decida entre reaproveitar/atualizar a existente ou abrir nova (ex: a existente
   está fechada há muito tempo, estagnada ou o escopo é diferente). Se houver correspondência
   parcial ou a busca não for conclusiva, apresentar ao usuário as candidatas encontradas antes de
   criar.
3. Coletar as demandas (título, US, solução).
4. Montar labels conforme regras do provider (label de status + label do projeto).
5. Para descrições longas ou com acentos, **usar arquivo temporário UTF-8** com `-d "$(cat ...)"`
   — o CLI pode truncar descrições longas ou corromper acentos (ver provider para o comando exato).
6. Atribuir milestone após criar, se informado.
7. Limpeza do arquivo temporário.

## Issues de Spec (Spec-Driven: spec-pai + fatias filhas)

Quando a demanda vem de uma **spec** (`specs/NNN-*/`, GitHub Spec Kit), **não abrir 1 issue para a
spec inteira**. Usar hierarquia nativa (mesma ideia do core+Tasks da `atividade-factory`, mas
planejada à frente em vez de registro retroativo):

| Situação da spec | Estrutura |
|---|---|
| Tem `tasks.md` | **Issue-pai** = a spec inteira + **1 filha por fatia que agrega valor** (1 PR coeso; nem uma tarefa solta, nem a spec toda). Preferir as fatias/PRs que o próprio `tasks.md` define; agrupar fases pequenas e contíguas, dividir as grandes. |
| Só tem `spec.md` (sem plan/tasks) | **Issue-pai** + **1 filha "Gerar plano e tarefas"** (`/speckit.plan`, `/speckit.tasks`, `/speckit.analyze`). Ao concluir essa filha, o fluxo exige **abrir as issues de implementação** da spec (filhas por fatia, como na linha acima) sob a mesma pai. |
| Spec entregue (tasks todas `[x]`) | Não criar issue. |

Só entram tarefas **pendentes** (`- [ ]`). Cada `T###` pendente aparece em **exatamente uma** filha.

### Regras

- **Título do pai:** `[Spec NNN] <Módulo> - Implementar <tema>` (prefixo entre colchetes é a exceção
  tolerada). **Título das filhas:** padrão normal `Módulo - Ação ...`, sem prefixo de spec.
- **Labels:** pai = `spec` + `spec:NNN`; filha = `spec:NNN` + tipo (`enhancement`) + `module:*`.
  A filha "Gerar plano e tarefas" leva também `speckit`.
- **Corpo da filha (template fixo, não variar entre execuções/subagentes):** `## US` →
  `## Valor entregue` → `## Tarefas da spec` (caminho do `tasks.md`, fatia e a lista literal
  `- [ ] T### descrição`) → `## Definition of Done` → `## Dependências`.
- **Corpo do pai:** link para `spec.md`/`plan.md`/`tasks.md`, resumo, estado (feito × pendente) e
  `## Definition of Done` (todas as filhas fechadas; `specs/INDEX.md` atualizado; nenhum `- [ ]`
  restante no `tasks.md`, salvo ações humanas documentadas). **Não repetir** a lista de filhas como
  texto longo: o widget de sub-issues já a mostra.
- **Definition of Done da filha — obrigatória em toda filha:** *marcar `[x]` no `tasks.md` as
  tarefas citadas na issue, **no mesmo commit/PR da solução***. Issue só fecha com isso feito; a
  filha cita as tarefas justamente para esse vínculo ser verificável.
- **Fechamento em cascata manual:** quando a última filha fecha, a spec terminou → fechar o pai
  (atualizando `specs/INDEX.md`). Fechar o pai **não** fecha as filhas automaticamente (conferir
  que todas estão fechadas antes) e vice-versa.
- **Anti-duplicata** (passo 2 do fluxo) vale também aqui: buscar por `spec:NNN` e pelos IDs
  `T###` antes de criar.
- **Ordem de criação:** pai → filhas (na ordem de implementação) → vincular cada filha ao pai como
  sub-issue → registrar dependências entre filhas no corpo. Comandos no provider.

## Fluxo — Adicionar Comentário com Solução

Antes de fechar uma issue, registrar a solução como comentário: commit hash, descrição técnica do
que foi feito, arquivos alterados (ver provider).

## Fluxo — Fechar Issue

1. Remover o label de status (ex: `In progress`).
2. Fechar a issue.

Se a plataforma bloquear alteração de datas em issue fechada o provider documenta o fluxo
alternativo (ex.: reabrir → definir datas → fechar).

## Fluxo — Definir Datas (start_date / due_date)

Algumas plataformas suportam datas por CLI; outras só por API/GraphQL. Seguir sempre o método documentado no provider — nunca assumir que o
CLI suporta o que a API restringe.

## Fluxo — Buscar Issues por Usuário em Todos os Projetos do Grupo

Listar projetos do grupo e filtrar issues por `assignee_username` + janela de datas (ver provider).

## Fluxo — Descobrir se uma Issue já foi Atribuída a Alguém no Passado

A listagem de issues só retorna o **estado atual** — não há histórico de assignee no payload. A
única fonte de verdade costuma ser a **nota de sistema** por issue (`assigned to @user` /
`unassigned @user`), o que exige 1 chamada por issue. Rodar em sequência é lento; **paralelizar com
`xargs -P`** reduz drasticamente o tempo (ver script completo no provider).

## Labels e Atribuição

Seguir o provider: quais labels existem, em qual grupo/escopo, e a tabela de usuários→username do
projeto. Ao criar a issue, sempre incluir o label do projeto + o label de status.
