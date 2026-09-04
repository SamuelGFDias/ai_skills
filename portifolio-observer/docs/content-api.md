# Contrato de conteúdo do portfólio

Fonte: `front/lib/content-service.ts` do repo do portfólio. Carregar antes de montar qualquer
payload de `PUT` — o JSON do banco é devolvido cru, sem normalizador, então um campo com nome
errado não dá erro, só nunca aparece no site.

## Tipos (`SiteContent`)

```ts
interface SiteContent {
  hero: {
    badge: string;
    titlePrefix: string;
    titleHighlight: string;
    titleSuffix: string;
    description: string;
    ctaPrimaryText: string;
    ctaPrimaryHref: string;
    ctaSecondaryText: string;
    ctaSecondaryHref: string;
  };
  techStack: {
    title: string;
    subtitle: string;
    categories: Array<{
      id: string;
      title: string;
      description: string;
      icon: string;   // ver "Valores válidos" abaixo — string livre, mas só resolve visualmente 3 valores
      color: string;  // idem — só 4 valores têm palette
    }>;
  };
  contact: {
    title: string;
    description: string;
    socialLinks: Array<{ platform: string; url: string; label: string }>;
  };
  footer: {
    text: string; // string simples exibida no rodapé; o og:image faz JSON.parse nela — não mexer no formato sem checar app/opengraph-image.tsx
  };
  projects: {
    title: string;
    subtitle: string;
    items: Array<{
      id: string;
      title: string;
      shortDescription: string;
      description: string;
      objective: string;
      technologies: string[];
      imageUrl: string;   // "" é válido — o componente cai pro logo (ProjectsShowcase.tsx: showLogo = !imageUrl || imgError)
      githubUrl: string;
      liveUrl: string;
      screenshots: Array<{ url: string; caption: string }>;
    }>;
  };
}
```

## Valores válidos (mapas hardcoded em `app/page.tsx`)

- `techStack.categories[].icon` — só resolve: `code`, `database`, `server`. Qualquer outro
  valor (ex.: `smartphone`, que já existe numa categoria publicada) cai silenciosamente no
  ícone de `code` — sem erro, sem aviso. Ao propor uma categoria nova, ou usar um desses três,
  ou sinalizar ao usuário que o `ICON_MAP` precisa de uma entrada nova antes.
- `techStack.categories[].color` — só resolve: `blue`, `emerald`, `purple`, `amber`.
- `contact.socialLinks[].platform` — `SOCIAL_COLORS` resolve: `github`, `linkedin`, `email`,
  `instagram`, `facebook`; qualquer outro cai no estilo `_default` (cinza).

## Rotas

### `GET /api/content`

Sem parâmetros, sem autenticação. Devolve o `SiteContent` completo.

```bash
curl -s https://portifolio.samueldias.dev.br/api/content
```

### `PUT /api/content`

Sem autenticação. Faz `{ ...current, ...body }` — **merge raso de um nível só**. Para editar
qualquer coisa dentro de `projects` ou `techStack`, o payload precisa levar o objeto de topo
**inteiro** (`projects` completo, com todos os `items`, não só o novo/alterado).

```bash
# 1. Ler o estado atual
curl -s https://portifolio.samueldias.dev.br/api/content > /tmp/current.json

# 2. Editar em memória (Python/jq) preservando os campos irmãos, então gravar
#    o objeto de topo INTEIRO de volta:
curl -s -X PUT https://portifolio.samueldias.dev.br/api/content \
  -H 'Content-Type: application/json' \
  --data @/tmp/projects-payload.json   # ex.: { "projects": { ...objeto completo... } }

# 3. Conferir
curl -s https://portifolio.samueldias.dev.br/api/content | jq '.projects.items | length'
```

### `POST /api/upload`

Multipart. Campos: `file` (binário) + `path` (string — **sempre** `projects/<project-id>`
para arquivos de projeto, senão a coleta de órfãos nunca limpa o arquivo). Aceita imagem ou
vídeo (vídeo passa por `ffmpeg`, ver `AGENTS.md` do portfólio). Retorna a chave pública em
`/api/files/<key>` — é esse valor que vai em `imageUrl`/`screenshots[].url`.

```bash
curl -s -X POST https://portifolio.samueldias.dev.br/api/upload \
  -F "file=@/caminho/screenshot.png" \
  -F "path=projects/proj-<id>"
```

## Exemplo de item de projeto (formato real, projeto já publicado)

```json
{
  "id": "proj-esoengenharia",
  "title": "Eso Engenharia",
  "liveUrl": "https://esoengenharia.seg.br",
  "imageUrl": "/api/files/projects/proj-esoengenharia/Design%20sem%20nome.png",
  "githubUrl": "",
  "objective": "Atuar como canal institucional e de captação de clientes B2B...",
  "description": "Descrição longa, aparece na página de detalhe do projeto...",
  "shortDescription": "Frase curta, aparece no card da lista.",
  "screenshots": [{ "url": "/api/files/projects/.../captura.png", "caption": "..." }],
  "technologies": ["Next.js", "TypeScript", "Tailwind CSS", "Keycloak", "Docker", "NextAuth"]
}
```
