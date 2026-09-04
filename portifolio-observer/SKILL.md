---
name: portifolio-observer
description: Observa, durante o trabalho em qualquer projeto pessoal do usuário, sinais de que a stack tecnológica real ou o perfil profissional evoluíram além do que está publicado no portfólio (https://portifolio.samueldias.dev.br) — um projeto que já está em produção e não aparece em `projects`, uma tecnologia/padrão amadurecido ausente de `techStack`, uma narrativa (`hero`/`footer`) desatualizada — e propõe (ou aplica, só com confirmação explícita) atualizações concretas ao conteúdo do site via sua API. Use quando: trabalhar em outro projeto pessoal (`~/dev/pessoal/front/*`) e notar algo relevante ausente do portfólio; o usuário pedir para revisar, auditar ou "atualizar" o portfólio; o usuário perguntar se o portfólio reflete o trabalho/stack atual; ou pedir para adicionar um projeto ao portfólio.
---

# Portifolio Observer

**Tipo:** internal

Skill irmã do `task-observer` — mesma metodologia (observar continuamente, logar sem
interromper o trabalho, revisar sob demanda, só agir com confirmação) — mas o alvo aqui não
são as skills: é o conteúdo do portfólio pessoal do usuário
(`/home/samueldias/dev/pessoal/front/portifolio`, produção em
`https://portifolio.samueldias.dev.br`). Leia o `AGENTS.md` desse repo antes de mexer em
qualquer coisa — ele documenta o contrato de conteúdo, a ausência de defaults/validação, e o
estado de segurança das rotas.

## Quando executar

- Trabalhando em qualquer outro projeto pessoal (`~/dev/pessoal/front/*` — hoje: `condominio`,
  `condominio_front`, `eso_engenharia`, `fio_e_forma` (+ `-catalogo`, `-composto`), `loja_vic`)
  e notar algo que merece aparecer no portfólio: projeto que foi para produção, tecnologia ou
  padrão novo, mudança de escopo de trabalho.
- Usuário pede para revisar, auditar ou "atualizar" o portfólio.
- Usuário pergunta se o portfólio reflete o trabalho/stack atual.
- Usuário pede para adicionar um projeto ao portfólio.

## O que observar

Sinal = divergência entre o portfólio publicado e a realidade observável. Três categorias:

1. **Projeto ausente** — projeto pessoal em produção (container rodando em `oracle-1`,
   domínio próprio, ou o usuário mencionando que "está no ar") que não aparece em
   `projects.items`.
2. **Stack desatualizada** — `techStack.categories` descreve tecnologias que já não
   representam o grosso do trabalho recente (ex.: hoje só cita C#/.NET + Flutter, mas os
   projetos recentes são majoritariamente Next.js + Postgres + Docker + Keycloak + MinIO).
3. **Narrativa desatualizada** — `hero.description`/`footer` descrevem uma especialidade que
   não bate mais com o trabalho predominante.

## Onde procurar evidência

- **Infra real:** `ssh ubuntu@oracle-1 "docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'"`
  lista todos os containers em produção. Cada serviço com domínio próprio (ver
  `/etc/nginx/conf.d/*.conf` dentro do container `nginx_global`) é candidato a projeto do
  portfólio. `docker exec <container> node -v` e grep no `package.json` dentro do container
  mostram a stack real, não a documentada.
- **Repos pessoais:** `~/dev/pessoal/front/*/AGENTS.md` documenta estado atual, stack e
  maturidade de cada projeto (ex.: "loja no ar, cobra dinheiro de verdade" é evidência forte
  de projeto pronto pra virar case).
- **Conteúdo publicado:** `GET https://portifolio.samueldias.dev.br/api/content` — snapshot
  atual de `hero`, `techStack`, `projects`, `footer`, `contact` (sem autenticação — ver
  `docs/content-api.md` para o contrato completo, os valores válidos de `icon`/`color`/
  `platform`, e a armadilha do merge raso no `PUT`).
- **Conversa:** o próprio usuário mencionando novo cliente, tecnologia aprendida, mudança de
  cargo/responsabilidade.

## Como logar

Mesma disciplina do `task-observer`: log silencioso, ao final do turno (ou a cada
checkpoint de tarefa), nunca guardado só em memória entre sessões. Workspace próprio, **não**
misturar com `~/.claude/skill-observations/` (aquele é do `task-observer`, sobre qualidade de
skills): usar `~/.claude/portfolio-observations/log.md` (criar com o cabeçalho abaixo se não
existir).

```markdown
### Observação [N]: [título curto]
**Status:** OPEN
**Data:** [data]
**Origem:** [projeto/sessão onde a divergência apareceu]
**Categoria:** [projeto-ausente | stack-desatualizada | narrativa-desatualizada]
**Evidência:** [o que foi observado, com caminho/comando/URL]
**Sugestão:** [mudança concreta de campo — valor atual → valor proposto]
```

Numeração: mesma disciplina do `task-observer` — ler o maior `N` já existente no log antes de
escrever (`grep -oP '### Observação \K\d+' log.md | sort -n | tail -1`), nunca reindexar de
memória.

## Como aplicar (só com confirmação explícita do usuário)

O conteúdo é a fonte de verdade do site em produção, sem validação nem defaults — carregar
`docs/content-api.md` antes de qualquer `PUT`. Checklist obrigatório antes de escrever:

1. `PUT /api/content` faz **merge raso** (`{...current, ...body}`): incluir uma chave de topo
   (ex. `projects`, `techStack`) **substitui o objeto inteiro**, não faz merge profundo.
   Sempre: `GET` do estado atual → clonar o objeto de topo inteiro que será tocado → editar só
   o necessário → enviar de volta o objeto completo (nunca um fragmento).
2. Upload de imagem: `POST /api/upload` (multipart, campo `file` + campo `path`). **Sempre**
   `path=projects/<project-id>` — a coleta de órfãos só varre esse prefixo; qualquer outro
   path (inclusive o default `uploads/`) nunca é limpo depois.
3. Não existe guarda de sessão nessas rotas (ver seção "Segurança" do `AGENTS.md` do
   portfólio) — isso não é licença para automatizar sem revisão, é conteúdo público ao vivo.
   **Sempre mostrar o diff proposto (campo → valor atual → valor novo) e esperar confirmação
   explícita antes do `PUT`.**
4. Depois do `PUT`, refazer o `GET` e conferir (a) que o campo mudou e (b) que nenhum campo
   irmão do mesmo objeto de topo sumiu — é exatamente o que a armadilha do item 1 quebraria
   silenciosamente.

## Revisão sob demanda

Quando o usuário pedir uma auditoria completa: rodar a varredura de infra (`oracle-1`) + grep
nos `AGENTS.md` de `~/dev/pessoal/front/*` + `GET /api/content`, montar a lista de
divergências das três categorias acima, e apresentar como proposta de diff item a item — não
aplicar nada em lote sem aprovação individual.
