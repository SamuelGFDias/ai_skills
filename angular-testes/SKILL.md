---
name: angular-testes
description: "Use ao escrever ou revisar teste unitário Angular em projeto da SES-RJ (ex.: `<NomeDoProjeto>.ClientApp`) — Karma/Jasmine ou vitest, TestBed, teste de classe pura sem Angular, e como rodar ng test (Chrome headless no Karma)."
---

# Skill: angular-testes

**Tipo:** internal

Conteúdo totalmente novo — a skill `angular-frontend` original não cobre testes. Escrita a partir
da leitura completa dos 6 `.spec.ts` reais do projeto e da execução real de `npm run test` nesta
máquina (seção 4).

## 1. Stack de teste e como rodar

**Antes de prescrever qualquer flag, detectar o runner do projeto alvo** em `angular.json`
(projeto → `architect` → `test` → `builder`) — o conjunto de flags que funciona é outro em cada
cenário:

| `builder` do alvo `test` | Runner | Como rodar |
|---|---|---|
| `@angular-devkit/build-angular:karma` (ou `@angular/build:karma`) | Karma + Jasmine | Cenário A abaixo |
| `@angular/build:unit-test` | vitest | Cenário B abaixo |

### Cenário B — vitest (`@angular/build:unit-test`)

O runner é o vitest, não o Karma: não há Chrome/`CHROME_BIN` a configurar (seção 2 não se
aplica) e o código de teste usa a API do vitest (`vi.fn()`, `vi.spyOn()`), não `jasmine.*`. Rodar
single run filtrando por arquivo, **sem `--browsers`**:

```bash
ng test --watch=false --include=<glob>      # ex.: --include='**/browser-storage.service.spec.ts'
```

`--browsers=ChromeHeadless` aqui **falha** com `requires @vitest/browser-*` (pede o provider de
browser do vitest, que o projeto não instalou) — é o sintoma de ter aplicado a receita do Karma
num projeto vitest. Se aparecer, remover `--browsers` em vez de instalar o pacote.

### Cenário A — Karma/Jasmine (o projeto de origem desta skill)

Confirmado em `package.json`: `"test": "ng test"`, com `karma` `~6.4.0`, `karma-chrome-launcher`
`~3.2.0`, `karma-jasmine` `~5.1.0`, `karma-jasmine-html-reporter` `~2.1.0`, `karma-coverage`
`~2.2.0`, `jasmine-core` `~5.6.0`, `@types/jasmine` `^5.1.15` — Karma + Jasmine, o padrão clássico
do Angular CLI.

**Não existe `karma.conf.js`** no repositório de origem (busca confirmada: nenhum arquivo desse
nome em `src/<NomeDoProjeto>.ClientApp`; verifique no projeto alvo, pois isso pode variar). O
builder `@angular-devkit/build-angular:karma` (declarado em
`angular.json`, projeto `client.app`, alvo `test`) lê a configuração diretamente do próprio
`angular.json` — `polyfills` (`zone.js`, `zone.js/testing`), `tsConfig: tsconfig.spec.json`,
`styles`/`scripts` (mesmos do build normal: Bootstrap, ngx-toastr, ngx-spinner, tema Material). É o
padrão mais recente do Angular CLI (builder moderno sem `karma.conf.js` separado) — não crie um
`karma.conf.js` manual esperando que ele seja lido; a config vive em `angular.json`.

Comando para rodar, a partir da raiz do repositório:

```bash
cd src/<NomeDoProjeto>.ClientApp
npm run test                                              # modo watch, abre Chrome real (interativo)
npm run test -- --watch=false --browsers=ChromeHeadless    # single run, sem watch — o que se usa em CI/verificação
```

## 2. Pegadinha real confirmada nesta máquina: binário do Chrome (só Cenário A — Karma)

Sem `CHROME_BIN` configurado, `karma-chrome-launcher` procura o binário padrão do Chrome/Chromium
no `PATH` e pode falhar com `No binary for ChromeHeadless browser on your platform` se não
encontrar. **Nesta máquina, `google-chrome`/`google-chrome-stable`/`chromium` não existem, mas
`/usr/bin/chromium-browser` existe** (confirmado via `which`). O comando que funcionou de fato:

```bash
cd src/<NomeDoProjeto>.ClientApp
CHROME_BIN=/usr/bin/chromium-browser npm run test -- --watch=false --browsers=ChromeHeadless
```

Resultado real desta execução: **8 de 8 testes passaram** (`Chrome Headless 150.0.0.0 (Linux
x86_64): Executed 8 of 8 SUCCESS`), cobrindo os 6 arquivos `.spec.ts` da seção 3 (alguns arquivos
têm mais de um `it`).

**O binário correto varia por máquina** — o mesmo problema já está documentado para o Karma do
projeto Biae (`~/dev/ses/back/new-biae/main/AGENTS.md`), que registra `/usr/bin/google-chrome`
como o binário disponível naquela outra máquina, e `chromium-browser` como alternativa quando
`google-chrome` não existe. Antes de rodar os testes numa máquina nova, confirme qual binário
existe (`which google-chrome || which chromium-browser || which chromium`) em vez de assumir que o
valor documentado aqui vale universalmente.

## 3. Dois padrões reais de teste encontrados

### 3.1 Classe pura, sem `TestBed`/Angular

Quando a unidade sob teste não depende de injeção do Angular (não é `@Component`/`@Injectable`
com dependências do framework, ou é uma classe/factory simples), o padrão real é instanciar a
classe direto com `new` — sem `TestBed.configureTestingModule` nenhum. Transcrição real de
`src/app/core/services/browser-storage.service.spec.ts:1-24`:

```typescript
import {BrowserStorageService} from './browser-storage.service';

describe('BrowserStorageService', () => {
  beforeEach(() => localStorage.clear());

  it('stores and reads JSON values', () => {
    const service = new BrowserStorageService();
    service.set('test:key', {value: 10});

    expect(service.get<{value: number}>('test:key')).toEqual({value: 10});
  });

  it('removes keys by namespace', () => {
    const service = new BrowserStorageService();
    service.set('test:one', 1);
    service.set('test:two', 2);
    service.set('other:key', 3);

    service.removeByPrefix('test:');

    expect(service.get('test:one')).toBeNull();
    expect(service.get('other:key')).toBe(3);
  });
});
```

Mesmo padrão em `src/app/shared/forms/consulta-filtro.form.spec.ts:1-25` — testa
`ConsultaFiltroFormFactory.create(...)` (uma factory estática que devolve um `FormGroup`)
chamando-a direto e fazendo asserção sobre o `FormGroup` retornado (`form.contains('nome')`,
`form.get('status')?.hasValidator(Validators.required)`), sem `TestBed`. `FormGroup`/`Validators`
do Angular são usados como classes normais aqui — não precisam de `TestBed` porque não dependem de
injeção de dependência nem de renderização.

**Quando usar este padrão**: services/factories/classes que não são `@Component` e cujas
dependências (se houver) são todas instanciáveis diretamente (sem `inject()`/construtor exigindo
providers do Angular).

### 3.2 Componente com `TestBed`/`ComponentFixture`

Para `@Component`, o padrão real usa `TestBed.configureTestingModule` para compilar o componente
(mesmo sendo standalone) e `ComponentFixture` para instanciá-lo. Transcrição real de
`src/app/app.component.spec.ts:1-19`:

```typescript
import { TestBed } from '@angular/core/testing';
import { AppComponent } from './app.component';
import { provideRouter } from '@angular/router';

describe('AppComponent', () => {
  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [AppComponent],
      providers: [provideRouter([])],
    }).compileComponents();
  });

  it('should create the app', () => {
    const fixture = TestBed.createComponent(AppComponent);
    const app = fixture.componentInstance;
    expect(app).toBeTruthy();
  });
});
```

Note `imports: [AppComponent]` (não `declarations`) — porque é standalone, o próprio componente
entra em `imports`. Quando o componente depende de providers do Angular (aqui, `provideRouter([])`
porque `AppComponent` usa `<router-outlet>`), eles são passados em `providers`.

Os três `.spec.ts` de `shared/components/tabela/` seguem exatamente o mesmo esqueleto, só trocando
o componente — transcrição real de
`src/app/shared/components/tabela/tabela-container/tabela-container.component.spec.ts:1-23`
(idêntico em estrutura a `table-actions.component.spec.ts` e `table-content/tabela.component.spec.ts`,
só troca `TabelaContainerComponent` pelo componente testado):

```typescript
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { TabelaContainerComponent } from './tabela-container.component';

describe('TabelaContainerComponent', () => {
  let component: TabelaContainerComponent;
  let fixture: ComponentFixture<TabelaContainerComponent>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [TabelaContainerComponent]
    })
    .compileComponents();

    fixture = TestBed.createComponent(TabelaContainerComponent);
    component = fixture.componentInstance;
    fixture.detectChanges();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
```

**Nota honesta**: esses três specs de `tabela/` são o esqueleto default gerado pelo Angular CLI
(`ng generate component`) — só verificam `expect(component).toBeTruthy()`, sem exercitar nenhuma
lógica real do componente (paginação, ordenação, ações de linha). Não os trate como exemplo de
cobertura significativa, só como exemplo do **padrão estrutural** (`TestBed` + `ComponentFixture`
para componente). Ao escrever um teste novo para um componente, siga esse esqueleto de setup, mas
adicione asserções que exercitem o comportamento real (inputs, outputs, interação), não pare em
`toBeTruthy()`.

**Quando usar este padrão**: qualquer `@Component` — mesmo sem dependência de outros providers,
`TestBed.createComponent` é necessário porque só ele resolve `templateUrl`/`styleUrl` e roda o
ciclo de detecção de mudanças (`fixture.detectChanges()`).

## 4. Convenção de nomenclatura — diferente da convenção do backend, de propósito

**Real, confirmado nos 6 arquivos**: `describe`/`it` em **inglês**, estilo idiomático Jasmine —
`describe('BrowserStorageService', () => { it('stores and reads JSON values', ...) })`,
`describe('AppComponent', () => { it('should create the app', ...) })`. Nenhum `describe`/`it` em
português foi encontrado em nenhum dos 6 specs.

**Isso é diferente da convenção obrigatória do backend .NET deste mesmo projeto**
(`dotnet-unit-tests`, seção 2): lá, a convenção é **português obrigatório**, sufixo `Testes` e
método `<Acao>_<Cenario>_<Deve...>` — decisão explícita do usuário para o backend, deliberadamente
diferente até do Biae (que usa `Tests` em inglês). **Não force essa convenção aqui.** O frontend
Angular segue o idiomático Jasmine em inglês (`describe('Componente', () => it('does something',
...))`), que é exatamente o que `ng generate component`/`ng generate service` já geram por padrão
e o que os 6 specs reais confirmam. Não decida migrar a nomenclatura de teste do frontend para
português por conta própria — se isso for desejado, é uma decisão de convenção nova a ser tomada
explicitamente pelo time, análoga à decisão que já foi tomada (e documentada) para o backend, não
algo a inferir por analogia.

Registro apenas como observação, não como TODO: backend e frontend deste projeto têm convenções de
nomenclatura de teste **intencionalmente diferentes** — português forçado no backend por decisão
explícita, inglês idiomático Jasmine no frontend por ser o padrão da ferramenta e não ter sido
alterado. Se algum dia o time quiser unificar, é uma escolha a ser feita, não uma inconsistência a
corrigir silenciosamente.

## 5. Checklist de revisão

- [ ] Conferiu o runner em `angular.json` (builder do alvo `test`) antes de passar flags? Karma
      aceita `--browsers=ChromeHeadless`; vitest (`@angular/build:unit-test`) não — use
      `ng test --watch=false --include=<glob>` (seção 1).
- [ ] Testando uma classe/factory sem dependência de DI do Angular? Instancie com `new` direto
      (seção 3.1) — não adicione `TestBed.configureTestingModule` desnecessário.
- [ ] Testando um `@Component`? Use `TestBed.configureTestingModule({imports: [Componente]})` +
      `ComponentFixture` + `fixture.detectChanges()` (seção 3.2) — `imports`, não `declarations`,
      porque os componentes do projeto são standalone.
- [ ] `describe`/`it` em inglês, estilo Jasmine idiomático — não confundir com a convenção
      obrigatória em português do backend .NET (`dotnet-unit-tests`).
- [ ] (Karma) Antes de rodar os testes numa máquina nova, confirme o binário do Chrome disponível
      (`which google-chrome || which chromium-browser || which chromium`) e passe via `CHROME_BIN`
      — não assuma que `/usr/bin/chromium-browser` (o que funcionou nesta máquina) existe em
      qualquer ambiente.
- [ ] Se o teste exercita um `FormGroup`/`FormControl` (formulário reativo), teste o `FormGroup`
      resultante diretamente (`form.contains(...)`, `form.get(...)?.hasValidator(...)`,
      `form.get(...)?.value`) em vez de simular interação de UI, quando a unidade sob teste é a
      classe de formulário (`angular-formularios`) e não o componente de página.
- [ ] Testes de componente vão além de `expect(component).toBeTruthy()` quando o componente tem
      comportamento não trivial — os três specs de `tabela/` citados na seção 3.2 são o piso
      mínimo gerado pelo CLI, não o padrão de qualidade a replicar.

## 6. Skills relacionadas

- `dotnet-unit-tests` — convenção de nomenclatura obrigatória em português do backend .NET; ver
  seção 4 acima para o contraste explícito com a convenção real do frontend.
- `dotnet-integration-tests` — equivalente de backend para teste que depende de infraestrutura real
  (banco via Testcontainers); não há equivalente de "teste de integração Angular" documentado hoje
  (nenhum spec do frontend sobe backend real ou usa `HttpClientTestingModule` — busca confirmou
  ausência de qualquer um dos dois nos 6 specs lidos).
- `tdd-first` — quando a demanda pede implementação orientada a teste; os dois padrões desta skill
  (seção 3) são os pontos de partida ao escrever o teste antes do código de produção no frontend.
- `angular-formularios` — classe de `FormGroup` tipada (`<entidade>.form.ts`), o alvo mais comum do
  padrão "classe pura sem `TestBed`" (seção 3.1) — `consulta-filtro.form.spec.ts` é exemplo real
  desse padrão aplicado a uma factory de formulário (escrita em paralelo a esta skill).
- `angular-listagens` — os componentes de `tabela/` cujos specs (esqueleto mínimo do CLI) são
  citados na seção 3.2 (escrita em paralelo a esta skill).
- `angular-frontend` — skill monolítica original; não cobria testes — esta skill preenche essa
  lacuna do zero.
