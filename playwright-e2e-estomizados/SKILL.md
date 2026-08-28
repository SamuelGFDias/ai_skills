---
name: playwright-e2e-estomizados
description: Receita fixa para escrever e corrigir specs e2e Playwright contra o ClientApp Angular (Material + Bootstrap) do Estomizados. Documenta os 4 padrões recorrentes que agentes independentes redescobrem por tentativa e erro: seeds com test.describe.configure serial, clique em mat-select recém-carregado, waits entre selects em cascata, e seletores de classe para dropdown Bootstrap com Popper. Use ao escrever, corrigir ou revisar specs e2e nesse projeto.
---

# Skill: playwright-e2e-estomizados

**Tipo:** internal — específica do projeto Estomizados (ClientApp Angular, Angular Material + Bootstrap).

## Padrão 1: beforeAll com seed via API exige `test.describe.configure({ mode: 'serial' })`

O `fullyParallel: true` do `playwright.config.ts` faz cada `test()` de um `describe` cair em worker próprio, e **cada worker roda seu próprio `beforeAll`**. Se o `beforeAll` faz seed via API com a mesma Idempotency-Key, os seeds concorrentes colidem em **HTTP 409**.

**Regra:** em todo `describe` cujo `beforeAll` faça seed via API, declarar logo após o `describe`:

```ts
test.describe.configure({ mode: 'serial' })
```

## Padrão 2: clique em mat-select recém-carregado esbarra no overlay

Um mat-select recém-renderizado tem o `.mdc-notched-outline` interceptando o ponto de clique, então o `click()` padrão falha (timeout de ação ou clique no elemento errado).

**Regra:** usar `.click({ force: true })` em mat-select recém-carregado.

## Padrão 3: waits entre selects em cascata — aguardar o overlay anterior sumir

Entre selects em cascata, o `aria-expanded` vira `false` **antes** da animação do `.cdk-overlay-pane` terminar. Abrir o próximo select cedo demais clica no painel antigo (que ainda está na tela durante o fade-out).

**Regra:** antes de abrir o próximo select em cascata, esperar o overlay anterior desaparecer:

```ts
await expect(page.locator('.cdk-overlay-pane')).toHaveCount(0)
```

## Padrão 4: itens de dropdown Bootstrap com Popper — usar seletor de classe, não `getByRole`

Botões dentro de dropdown Bootstrap posicionado via Popper (`position: fixed`) reportam `isVisible() === false` para `getByRole` mesmo com `aria-expanded="true"` e classe `.show` — a árvore de acessibilidade do Chromium não acompanha o reposicionamento a tempo.

**Regra:** usar seletor de classe (`.dropdown-item`) em vez de `getByRole` para interagir com itens de dropdown Bootstrap com Popper.

```ts
await page.locator('.dropdown-item', { hasText: 'Opção' }).click()
```

## Anti-padrão: `test.skip(condição, 'usuário sem role X')` como diagnóstico

Ao investigar um teste que não roda, **não** aceitar o motivo de um `test.skip` como fato. "Usuário sem role X" pode ser diagnóstico falso: o locator pode estar não-escopado ou quebrar pelo timing do Popper (padrões 3 e 4) sem que falte permissão alguma.

**Regra:** antes de atribuir um skip a falta de permissão, confirmar com sonda: decodificar o token/claims reais e/ou inspecionar o elemento num script Playwright avulso.
