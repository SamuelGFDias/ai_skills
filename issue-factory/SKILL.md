---
name: issue-factory
description: Workflow genérico de gestão de issues (criar, comentar solução, fechar, milestones, datas, padrão de título) independente da plataforma. Os comandos concretos da plataforma ficam em providers/ — GitLab em providers/gitlab/arquivos.md. Use quando o usuário pedir para abrir, atualizar ou fechar issues em um tracker de tarefas.
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

Onde cada label/milestone vive é definido pelo provider (ex.: GitLab separa labels entre o grupo
`ses-rj/` e `ses-rj/desenvolvimento/` — ver `providers/gitlab/arquivos.md`).

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
   **obrigatória, nunca pulável** (comando por provider: GitLab/GitHub). Buscar nos campos de título
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

## Fluxo — Adicionar Comentário com Solução

Antes de fechar uma issue, registrar a solução como comentário: commit hash, descrição técnica do
que foi feito, arquivos alterados (ver provider).

## Fluxo — Fechar Issue

1. Remover o label de status (ex: `In progress`).
2. Fechar a issue.

Se a plataforma bloquear alteração de datas em issue fechada (ex: GitLab), o provider documenta o
fluxo GraphQL: `REOPEN` → definir datas → `CLOSE`.

## Fluxo — Definir Datas (start_date / due_date)

Algumas plataformas suportam datas por CLI; outras só por API/GraphQL (ex: `start_date` no GitLab
18.x só via `workItemUpdate`). Seguir sempre o método documentado no provider — nunca assumir que o
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
