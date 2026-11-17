---
name: portfolio-conteudo
description: "Mantém atualizado o conteúdo de um site de portfolio servido por API (seção comercial, projetos, serviços, etapas, dúvidas, contato) sem deploy: lê e grava pelo endpoint /api/content, envia imagens por /api/upload e faz backup antes de cada escrita, com o token vindo de arquivo protegido ou do cofre. Use quando pedirem para adicionar ou editar um projeto do portfolio, trocar um texto, número de WhatsApp, serviço ou pergunta frequente, ou subir screenshots novos."
---

# Skill: portfolio-conteudo

**Tipo:** internal

## Quando executar

- "Adiciona o projeto X ao portfolio", "atualiza o texto do hero", "troca o WhatsApp", "põe mais uma dúvida", "sobe estes screenshots".
- Não usar para mudar layout, cores ou código: isso é alteração no repositório do site, com deploy.

## Configuração

O site é escolhido por configuração, nunca pelo código. Variáveis (ambiente ou `~/.config/portfolio-conteudo/env`, permissão 600):

| Variável | Para quê |
|---|---|
| `PORTFOLIO_URL` | **Obrigatória.** URL base do site, sem barra final (ex.: `https://<dominio>`). |
| `PORTFOLIO_TOKEN_FILE` | Arquivo 600 com o token da API (`CONTENT_API_TOKEN` do site). |
| `PORTFOLIO_TOKEN_REF` | Alternativa: referência no cofre, lida com `vault-read` (skill `vault-factory`). |

O token nunca é impresso, nem passado em argumento: o script monta um arquivo de cabeçalho temporário 600 e o apaga ao sair.

## Comandos

```bash
P=~/.config/ai/skills/portfolio-conteudo/scripts/portfolio.sh
$P get [secao]                     # leitura, sem token (o conteúdo é público)
$P backup                          # cópia em ~/.config/portfolio-conteudo/backups/
$P set <secao> <campo> <valor>     # um campo de texto; ex.: set commercial whatsappNumber 5521999998888
$P project-upsert <projeto.json>   # cria ou atualiza um projeto pelo "id", preservando os outros
$P upload <arquivo> <pasta>        # ex.: upload tela.png projects/proj-x  → imprime a URL /api/files/...
$P put <arquivo.json>              # substitui seções inteiras de topo; usar por último
```

`set`, `project-upsert` e `put` fazem backup antes de gravar. Para desfazer: `$P put <backup.json>`.

## Modelo de conteúdo

Seções de topo: `commercial` (página inicial, voltada a clientes), `projects`, `hero`, `techStack` e `contact` (página `/dev`), `footer`.

- **`commercial`**: `heroTitle`, `heroLead`, `ctaPrimaryText`, `ctaSecondaryText`, `whatsappNumber` (só dígitos, com DDI e DDD; vazio faz os botões usarem o e-mail), `whatsappMessage`, `worksTitle`, `worksIntro`, `servicesTitle`, `services[] {title, description, example}`, `stepsTitle`, `steps[] {title, description}`, `aboutTitle`, `aboutText`, `faqTitle`, `faq[] {question, answer}`, `closingTitle`, `closingText`, `seoTitle`, `seoDescription`.
- **`projects.items[]`**: `id` (`proj-<slug>`), `title`, `shortDescription`, `description` (técnica, aparece em `/dev`), `objective`, `technologies[]`, `imageUrl`, `mobileImageUrl` (captura em tela de celular), `screenshots[] {url, caption}` (a primeira é a capa), `liveUrl`, `githubUrl`, e os campos da versão comercial: `kind`, `commercialSummary`, `fact`, `hideOnCommercial`.

A ordem de `projects.items` é a ordem na página; o primeiro é o destaque.

## Fluxo: adicionar um projeto

1. **Levantar os fatos na fonte** (README do repositório, o site no ar). Nada inventado: sem depoimento, número, cliente ou prazo que a fonte não dê. O `fact` é uma frase verificável hoje.
2. **Imagens**: uma captura de computador (1440×900) e uma de celular (390 de largura) do site no ar. Sem navegador na máquina, o contêiner `mcr.microsoft.com/playwright` com `--network host` resolve. Conferir antes que o site responde 200.
3. `upload` de cada imagem em `projects/<id>`; guardar as URLs devolvidas.
4. Escrever `projeto.json` com os campos acima e rodar `project-upsert`.
5. Conferir: `get projects` e abrir a página.

## Texto (versão comercial)

- Linguagem de cliente, sem jargão: o que o projeto resolve, não como foi construído. O técnico vai em `description`.
- Título de serviço e de etapa nomeia a coisa; botão é verbo mais objeto.
- Compromissos de prazo, preço e atendimento são do dono do site: só escrever o que ele confirmou.

## Armadilhas

- **`put` substitui a seção de topo inteira.** Gravar `{"projects": {...}}` com um projeto a menos apaga esse projeto. Preferir `set` e `project-upsert`.
- **Arquivo sem referência vai para a lixeira.** A cada gravação, o site move para o bucket `<bucket>-trash` os arquivos de `projects/` que nenhum campo cita. Enviar a imagem e gravar o conteúdo que a referencia na mesma sessão; para trocar uma imagem, gravar a URL nova antes de considerar a antiga perdida.
- **401** é token errado ou ausente; **403** é sessão de painel sem e-mail na lista de admins. A escrita falha fechada quando o site está sem `CONTENT_API_TOKEN`.
