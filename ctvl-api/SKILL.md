---
name: ctvl-api
description: Gerencia o CT-VL (CipherTrust Vaulted Tokenization) pela API admin e ajuda a configurar templates, tokengroups, máscaras, usuários, grupos e permissões de token por sistema (sindras, biae, settorj) de forma declarativa — listagem da configuração atual, export YAML versionável e sem segredos, plan/apply idempotente e verificação de máscara — sem expor senha nem JWT. Use quando o usuário pedir para consultar, comparar, exportar, planejar ou aplicar a configuração do CT-VL/vault de tokenização (dev/hml/prd), criar template/usuário/máscara para um sistema, ou verificar o que um usuário mascarado do vault enxerga.
---

# Skill: ctvl-api

**Tipo:** internal

Encapsula a API **admin** do CT-VL (Swagger 2.0, `basePath /api`, JWT por `POST /api-token-auth/`) e a API de **dados** (`/vts/rest/v2.0/tokenize|detokenize`, Basic) para o projeto Sindras e sistemas vizinhos. Segue o modelo da skill `keycloak-api`: credenciais em arquivo local protegido, scripts que nunca imprimem segredo, um CLI único (`ctvl.sh`).

> **Nada aqui foi executado contra o vault real durante a criação da skill.** A validação foi offline (fixtures e servidor falso em loopback). Tudo que o swagger não prova está em **"A confirmar"** (seção final) e os scripts falham com mensagem clara em vez de adivinhar.

## Regras de segurança (valem sempre)

1. **A credencial admin é fornecida pelo usuário, explicitamente.** Nunca peça nem aceite colar a senha no chat. Se ela aparecer no chat, avise que deve ser rotacionada.
2. **Credencial de dados NÃO vale na API admin.** O usuário de tokenize/detokenize (ex.: `*_svc_tokenize`, `CTVL_TOKENIZE_*`, os usuários de máscara) existe para a API de dados. Usá-lo para logar na API admin não é permitido, mesmo que "funcione". Registro: num trabalho anterior, uma tentativa de login admin com a credencial do usuário de tokenize foi **barrada pela camada de permissão** da sessão. Isso é o comportamento esperado e correto: **não contorne, não retente**, peça ao usuário a credencial admin (ou que rode `ctvl.sh setup-env`).
3. Senha e JWT **nunca** são impressos, nunca vão em argumento de linha de comando (aparece em `ps`/histórico) e nunca entram em arquivo versionado. O JWT fica em cache `~/.cache/ctvl-api/<amb>.jwt` (modo 600, diretório 700) com um selo `<amb>.jwt.bind` (hash de apelido+host+usuário admin; o host nunca vai em claro): se o `HOST`/`ADMIN_USER` do apelido mudar, o token é descartado e nunca reenviado a outro host (`setup-env` também limpa o cache do apelido). A senha só existe no arquivo de credenciais (600) ou em `CTVL_ADMIN_PASSWORD_<AMB>` (apelido em maiúsculas, `-` vira `_`; ex.: `CTVL_ADMIN_PASSWORD_DEV`) no terminal do usuário. A variável global `CTVL_ADMIN_PASSWORD` foi **aposentada**: é ignorada (com aviso, sem imprimir valor), porque valia para todos os ambientes. Toda `CTVL_ADMIN_PASSWORD*` é removida do ambiente do motor Python antes de qualquer chamada, então nenhum `password_ref` consegue lê-la.
4. A saída de todos os scripts passa por mascaramento: JWT, `Authorization`, campos de senha/hash/segredo, IPs (v4/v6, inclusive o `(X-Real-IP '...')` dos erros do vault) e o host viram `***`/`<ip>`/`<host>`.
5. **Escrita é sempre explícita**: `admin POST|PUT|PATCH|DELETE` exige `--yes`; `apply` exige `--yes`. Antes de qualquer envio, o script imprime o que vai fazer (método, URL sem host, corpo com segredos mascarados). **Nada é deletado** pelo `apply`; remoção só manual, via `admin DELETE ... --yes`, a pedido do usuário.
6. TLS: use `CA_BUNDLE` por ambiente. `INSECURE_TLS=1` só por opção explícita e **apenas** nos apelidos `dev`, `hml`, `fake` ou num apelido com `<amb>.TIER=nonprod` no arquivo de credenciais; qualquer outro (`prd`, `prod`, `producao`, `prd2`...) é recusado, e `<amb>.TIER=prod` recusa até `dev`/`hml`. `setup-env` nem oferece a opção nos apelidos não liberados. Cada uso imprime aviso.
7. Em dúvida entre ler e escrever, leia. Ambiente `prd`: só com pedido explícito do usuário, sempre `plan` antes de `apply`.

## Ambientes e credenciais

Apelidos `dev`, `hml`, `prd` → host, definidos em `~/.config/ai/ctvl/credentials` (**fora do git**, modo 600; o script recusa outro modo). Modelo: `credentials.example` desta skill.

```
dev.HOST=<host>            dev.ADMIN_USER=<admin>        dev.ADMIN_PASSWORD=<senha>
dev.CA_BUNDLE=...          dev.INSECURE_TLS=0|1          dev.ADMIN_BASE_PATH=/api   dev.DATA_BASE_PATH=/vts/rest/v2.0
dev.TIER=nonprod|prod      (opcional; nonprod libera INSECURE_TLS em apelido fora da lista dev/hml/fake)
```

- O arquivo é lido linha a linha (split no 1º `=`); nunca `source`/`eval`: nada nele executa e uma chave estranha não sobrescreve variável de shell.
- **Cadastro:** `ctvl.sh setup-env <amb>` (interativo, senha com eco `*`, grava 600). O usuário roda num terminal à parte ou no Claude Code com o prefixo `!`. `ctvl.sh envs` lista o que está configurado **sem** mostrar host, usuário nem senha.
- Se `ctvl.sh envs` não mostra o ambiente pedido, ou falta a credencial admin, **peça ao usuário** para cadastrar. Não procure senhas em `.env*` do projeto (ex.: `.env.Development`) nem em variáveis do usuário de dados.
- Senhas dos usuários de dados (verificação de máscara) vêm de variáveis de ambiente do shell do usuário (ex.: carregadas pela skill `vault-factory`), nomeadas por `password_ref`. O `password_ref` só aceita `env:CTVL_<NOME>_PASSWORD` (`^CTVL_[A-Z0-9_]+_PASSWORD$`); `env:CTVL_ADMIN_PASSWORD*`, `env:CTVL_LOGIN_*` e qualquer outro nome (`env:HOME`...) são recusados na carga do arquivo. O `plan` mostra sempre o **nome** da variável de cada usuário a criar (nunca o valor). Um usuário cujo nome derivaria a senha admin (ex.: `admin` → `CTVL_ADMIN_PASSWORD`) pode existir no arquivo, mas a sua CRIAÇÃO fica BLOQUEADA.

## Comandos (`scripts/ctvl.sh <subcomando>`; caminho completo: `~/.claude/skills/ctvl-api/scripts/ctvl.sh`)

| Subcomando | O que faz | Escreve? |
|---|---|---|
| `setup-env <amb>` / `envs` | cadastra / lista ambientes | só o arquivo local |
| `token <amb> [--refresh\|--status]` | garante o JWT em cache; **nunca imprime o token** | não |
| `admin <amb> <MÉTODO> <path> [--body-file F\|--body-stdin\|--body JSON] [--query k=v] [--all] [--yes]` | cliente genérico; mascara a saída | só com `--yes` |
| `list <amb> <recurso> [--format table\|yaml\|json]` | configuração atual: `masks users groups tokengroups templates charsets keys formats permissions all` | não |
| `export <amb> [--out arq.yaml]` | YAML declarativo, determinístico, sem segredos | não |
| `probe-refs <amb>` | evidência de nome x id nas referências (sem imprimir valores) | não |
| `plan <amb\|--offline> --file CFG \| --docs-dir DIR [--verbose]` | diff: `CRIAR`/`ATUALIZAR`/`OK`/`CONFLITO`/`MANUAL`/`BLOQUEADO`. **Saída compacta por padrão** (ver "Saída compacta" abaixo); `--verbose` ou `CTVL_VERBOSE=1` restaura o texto completo de cada item | não |
| `apply <amb> --file CFG \| --docs-dir DIR --yes` | aplica o plano (idempotente) e replaneja para verificar. **Atribui a máscara declarada** ao usuário (lê `GET /users/{id}` e faz `PUT /users/{id}` com `username` e `email` atuais + `"mask": "<nome>"`; usuário LDAP: só `{"mask"}`) e relê o usuário: falha fechado (exit != 0) se `mask` lido != declarada ou se email/is_active/is_staff/is_superuser/groups mudaram. Aceita `--verbose`/`CTVL_VERBOSE=1` (o `EXECUTA` por escrita vira o par `EXECUTA ... corpo=` + `-> HTTP`) | só com `--yes` |
| `verify-mask <amb> --file CFG --sistema S --datatype D --sample VALOR` | tokeniza com o serviço, detokeniza com cada usuário e compara | não (API de dados) |
| `enable-detokenize <amb> <usuario> --file CFG [--yes] [--sample V]` | **único** caminho que escreve `canGet=true` para perfil mascarado, um usuário por vez. Sem `--yes` é dry-run. Pré-condições (falham fechado, sem escrever): (a) usuário existe e é mascarado no arquivo com detokenize declarado; (b) máscara atribuída = declarada (exata) e `user.mask` resolve; (c) máscara existe no vault com os mesmos parâmetros e não está `a_confirmar`; (d) nenhum grupo do usuário com `canGet=true`; (e) senhas `CTVL_*_PASSWORD` do usuário e do usuário de tokenize no ambiente; (f) referências de escrita confirmadas e chave sem compartilhamento não autorizado. Depois do PUT/POST roda o `verify-mask` só desse usuário e **reverte para `canGet=false`** se divergir ou falhar | só com `--yes` |
| `names NOME... [--kind user\|mask]` / `check-config --file CFG` | valida convenção de nomes / configuração (offline) | não |

Detalhes úteis:
- **Saída compacta (padrão de `plan` e `apply`)**: `Plano <amb> (<sistema>)`, uma linha de contagem dos `OK` por tipo (`OK (16): chave, tokengroup, 2 templates, ...`), `A FAZER (N)` com uma linha por item não-OK (`ATUALIZAR usuário X   máscara: nenhuma -> Y`), `BLOQUEIOS E CONFLITOS` e `AVISOS E PENDÊNCIAS MANUAIS` **sempre com o motivo completo**, uma linha `DEPOIS (enable-detokenize, 1 por usuário): N pendentes` com os nomes, o rodapé `Bloqueios | Avisos | Conflitos` e até 3 linhas de `Legenda`. No `apply`, uma linha por escrita (`EXECUTA PUT /users/2 (usuário X) -> HTTP 200`) e `Verificação (replanejamento): N ação(ões) ainda pendente(s) (esperado 0)`. `--verbose` (ou `CTVL_VERBOSE=1`) mostra o texto completo de hoje, com corpos e a explicação por linha. Só muda a apresentação: planos, escritas, exit codes e AVISOS são os mesmos; `plan --check` idem.
- `list users` mostra a **máscara** de cada usuário (`(sem máscara: vê completo)` quando não há), os **grupos** e `sistema/datatype/esquema`; nomes fora da convenção aparecem como `FORA DO PADRÃO` e num aviso final.
- `list`/`export`/`plan`/`probe-refs` aceitam `--state-dir DIR` (respostas de GET gravadas em `DIR/<path com / trocado por __>.json`, ex.: `tokentemplates.json`, `permissions__token__users.json`) e `plan` aceita `--empty-state`: rodam **sem rede**.
- `plan --docs-dir` lê `templates.yaml` + `usuarios-e-mascaras.yaml` (+ cruza `perfis-keycloak.yaml`) de `docs/tokenizacao-ctvl/`. Template legado `SES` (`uso: NAO_USAR_EM_PRODUCAO`) é ignorado salvo `--include-legacy`. Não há chave no YAML do projeto: informe `--key-map SINDRAS=<nome-da-chave>` ou o tokengroup fica `BLOQUEADO` (se já existir no vault, a chave dele é usada). Use `--email-domain` (e-mail é obrigatório na API).
- `plan --check` sai com 1 se houver mudança, bloqueio ou pendência manual (uso em CI).
- Códigos de saída: `apply` sem `--yes` = 2; bloqueios sem `--skip-blocked` ou pré-requisito faltando (referência a confirmar, variável de senha ausente) = 3, **antes de qualquer escrita**.

## Modelo mental do vault (confirmado pela equipe do vault)

- O **template** é a receita do token: formato (FPE x random), charset, `keepleft`/`keepright`, prefixo, reversibilidade. **Tokenizar e detokenizar usam o MESMO template.**
- A **máscara da detokenização é definida pelo usuário** do vault (campo `mask` do usuário), não pelo template. Usuário **sem máscara vê o dado completo**.
- O swagger marca `mask` como `readOnly` em `User`/`Group` e não tem endpoint de atribuição, mas **isso é impreciso**: medido em DEV (2026-10-08, Swagger UI), `PUT /api/users/{id}` com corpo mínimo `{"mask": "cns_3_left"}` (em usuário **LDAP**; usuário **local** exige também `username`/`email`, ver "A confirmar" nº 4) devolve HTTP 200 e `"Mask successfully updated."`, e o `GET /users/{id}` seguinte mostra `"mask": "cns_3_left"`. O valor é o **NOME** da máscara (não o `idmask`); a UI web faz o mesmo PUT em `/users/{id}`. Por isso o `apply` **atribui a máscara** (usuário novo: POST e depois o PUT; usuário existente sem máscara: ATUALIZAR). Usuário com máscara **diferente** da declarada é `CONFLITO` (não sobrescreve). **Não medido**: remover a máscara (`null`/`""`) e se **grupo** herda máscara; a skill não implementa nenhum dos dois. Ver "A confirmar" nº 4. `references/endpoints.md` é gerado do swagger e continua dizendo `readOnly`.
- Pelo swagger: as permissões de token (`canPost` tokenizar, `canGet` detokenizar) são por **chave** (`key`), não por template. Todo tokengroup que usa a chave herda a permissão. Se dois datatypes (cpf e cns) compartilham a chave, um usuário "de cpf" também poderia detokenizar cns. **Isolamento por datatype exige chaves (e tokengroups) distintos**: decidir com a equipe do vault.

## Configuração por sistema: convenção e herança

Nome do usuário: **`<sistema>_<datatype>[_<esquema>]`** (sistemas: `sindras`, `biae`, `settorj`; datatypes: `cpf`, `cns`; usuário de serviço: `<sistema>_svc_tokenize`; usuário sem máscara: `<sistema>_total`; reservados: `svc`, `total`). Usuário sem máscara é **um por sistema, não um por campo** (a máscara é atributo do usuário do vault: um `<sistema>_total` com `canGet` vê todos os datatypes em claro). `total` não vale em máscara. Máscara: `[<sistema>_]<datatype>_<esquema>`.

- `cns_3_left` = esquema de máscara (3 à esquerda). `sindras_cns` = usuário **genérico/padrão para testes**. `settorj_cns` = usuário com a **configuração do sistema**. O ideal é cada sistema ter a sua; `sindras_*` é o fallback de teste.
- Arquivo declarativo com `defaults` (catálogo de máscaras, template e usuários padrão por datatype) e `sistemas` (overrides por sistema: máscaras, usuários, templates, tokengroup, chave, permissões), que **herdam** de `defaults`. Esquema completo, tabela de campos e regras de herança: `references/schema-config.md`. Exemplo versionável (defaults + sindras + settorj, CPF 3 à esquerda e 2 à direita com `*`, CNS 3 à esquerda): `references/exemplo-config.yaml`.
- O parser de nomes (`names`) extrai sistema/datatype/esquema e **reporta** (não ignora) o que está fora da convenção. Usuários legados `ctvl_*` aparecem assim.

## Fluxos

### Levantar a configuração atual
`ctvl.sh list <amb> all` (tabelas) ou `--format yaml`. Para versionar: `ctvl.sh export <amb> --out ctvl-<amb>.yaml` e commitar o arquivo no projeto (é determinístico; o `git diff` mostra só mudança real). Para comparar ambientes: exporte `dev` e `hml` e use `diff`.

### Configurar (declarativo)
1. Escreva/ajuste o YAML (`references/exemplo-config.yaml`). Itens pendentes de decisão (charset `PENDENTE`, máscara `status: a_confirmar`) **bloqueiam** só aquele item.
2. `ctvl.sh plan <amb> --file cfg.yaml` e **mostre o plano ao usuário** (saída compacta; use `--verbose` se ele quiser o detalhe de cada item). Não aplique sem ele ver.
3. `ctvl.sh probe-refs <amb>`; se necessário declare `api.refs` no YAML (ver "A confirmar" nº 3). Sem isso, a escrita aborta antes de enviar algo.
4. O usuário exporta as senhas dos usuários **novos** no próprio shell (`CTVL_<USUARIO>_PASSWORD`; só os nomes aparecem no plano). Nunca peça os valores. Tokengroup em `CONFLITO`/`BLOQUEADO` (ex.: a chave declarada difere da atual) leva junto o template, as permissões dele e o usuário criado só para elas: ficam `PULADO` no `--skip-blocked`, e a permissão cuja chave difere da chave atual do tokengroup no vault fica `BLOQUEADO`; se o formato da referência `tokengroup.key` não for comparável (evidência inconclusiva), ela também fica `BLOQUEADO` até declarar `api.refs.tokengroup.key` (rode `probe-refs`). Tokengroup cuja chave também é usada por outro tokengroup (no vault **ou declarado no mesmo arquivo**, ex.: dois sistemas com a mesma chave num vault vazio) fica `BLOQUEADO` ao ser criado, e a permissão/usuário que o YAML pede para **aumentar** (criar ou subir flag) sobre essa chave também (rebaixar nunca é bloqueado; permissão só por `chave`, sem `tokengroup`, também é bloqueada quando a chave tem mais de um tokengroup sem opt-in) (permissão é por chave: herdaria o acesso do outro), salvo opt-in nomeado `chave_compartilhada: true` em **cada** tokengroup que compartilha. Um compartilhamento que já existe no vault (ex.: `SES` e `defaultGroup` sobre `CTS` no DEV) não é bloqueado: só o que o YAML pede para criar/atualizar. A permissão com `tokengroup` compara SEMPRE a chave efetiva (declarada, herdada do tokengroup do arquivo ou da permissão) com a chave real do tokengroup no vault e fica `BLOQUEADO` se diferirem, ou se `tokengroup.key` estiver sem evidência (declare `api.refs.tokengroup.key`); chave diferente da declarada para o tokengroup também bloqueia.
5. `ctvl.sh apply <amb> --file cfg.yaml --yes` (a pedido). O script cria em ordem: chave → charset → grupo → tokengroup → template → máscara → usuário → permissões; para no primeiro erro; replaneja ao final (esperado 0 pendente).
6. Resolver as **pendências manuais** listadas no fim do plano e do `apply` (a máscara declarada **não** é mais uma delas: o próprio `apply` a atribui). **Regra única: o `apply` nunca escreve `canGet=true` para perfil mascarado** (usuário com `mascara` declarada no arquivo OU com máscara atribuída no vault, em qualquer estado da máscara: confirmada, `a_confirmar`, bloqueada, diferente da declarada, referência que não resolve) nem para permissão de **grupo** que tenha algum membro mascarado (atual no vault ou declarado em `usuarios[].grupos`): a permissão é escrita com `canGet=false` (`canPost` como declarado), inclusive rebaixando um `true`. O **rebaixamento é uma passagem independente**, calculada ANTES de qualquer bloqueio da permissão: se o vault já tem linha de permissão do usuário mascarado sem máscara confirmada (ou de grupo com membro mascarado) com `canGet=true`, o plano cria uma ação `ATUALIZAR` própria (`<perm> [rebaixar canGet]`) só com `canGet` true -> false, usando o id e a chave da linha que o vault já tem (`canPost` atual intocado, `asymkey`/`opaqueobj` null, nunca `true`), executada também com `--skip-blocked`. Nenhum desses impedimentos a derruba: sujeito `BLOQUEADO` (máscara `a_confirmar`/bloqueada/inexistente, id do usuário não devolvido), chave da permissão diferente da do tokengroup no vault ou da declarada, `tokengroup.key` não comparável, tokengroup em `CONFLITO`/`BLOQUEADO`. Permissão duplicada (várias linhas para o mesmo par): TODAS as linhas com `canGet=true` são rebaixadas, uma ação por id; o resto da duplicata segue `CONFLITO`. Qualquer outra mudança na permissão (ex.: `canPost` true) continua respeitando todos os bloqueios. **Exceção explícita (rebaixamento NÃO aplicável):** referência `perm_*` (`perm_user.key`, `perm_group.group`, `perm_group.key`) sem formato confirmado para escrita (evidência inconclusiva, ou lida por evidência mas sem `api.refs`), ou permissão sem id devolvido: o PUT não é montável e a skill não inventa; entra `AVISO: ... NÃO é aplicável ... PERMANECE` nas pendências manuais (declare `api.refs` via `probe-refs` e reaplique, ou rebaixe na GUI). Linha de permissão de mascarado para chave que o arquivo NÃO declara não é vista por esta passagem (só pares usuário/grupo+chave do arquivo); o plano só avisa (ver limites abaixo). **Sem `--skip-blocked` o `apply` aborta (rc 3) e NADA é escrito**: o `canGet=true` permanece no vault; o plano traz `AVISO: ... PERMANECE` nas pendências manuais (`plan --check` falha em todos esses caminhos) e a mensagem de aborto diz "ATENÇÃO: N permissão(ões) mascarada(s) mantêm canGet=true no vault; use --skip-blocked para aplicar os rebaixamentos (e o resto não bloqueado do plano)"; aplique-os com `apply --skip-blocked`. Perfil sem máscara (perfil total) segue o `detokenize` declarado. Fluxo: `apply` (cria o usuário, atribui a máscara e relê) → `ctvl.sh enable-detokenize <amb> <usuario> --file cfg.yaml` (dry-run) → o mesmo com `--yes`. O `plan` lista uma vez por usuário "HABILITAR DETOKENIZE pendente"; depois do enable o `plan`/`apply` preservam o `true` que ele escreveu (não rebaixam enquanto a máscara continuar exatamente a declarada). Usuário NOVO mascarado num grupo que já tem `canGet=true` no vault fica `BLOQUEADO` (ver "A confirmar" nº 15).
   Limites conhecidos remanescentes da regra única (só `AVISO` nas pendências manuais, `plan --check` rc 1, nenhum PUT):
   - referência `perm_*` não confirmada ou linha sem id: o rebaixamento não é montável, só AVISO;
   - permissão sem chave resolvível: só AVISO pelo sujeito (não há como achar a linha);
   - permissões `canGet=true` de usuário mascarado declarado em chaves que o arquivo não declara: só AVISO (declare a permissão no arquivo ou ajuste na GUI); usuários fora do arquivo nunca são varridos.

### Runbook: ordem de configuração de um sistema novo
1. Decidir com a equipe: nome do sistema, tokengroup, **chave** (compartilhada ou própria), charset (ASCII imprimível x numérico) e a LGPD do `keep_left`/`keep_right`.
2. Chave e (se custom) charset → tokengroup → template (`<SISTEMA>_<DATATYPE>`, mesmo template para ida e volta) → máscaras → usuário de serviço (tokenize) → usuários de detokenização por esquema → permissões na chave.
3. O `apply` já atribuiu as máscaras aos usuários (se algum ficou em `CONFLITO`, corrigir à mão antes); só então rodar `ctvl.sh enable-detokenize <amb> <usuario> --file cfg.yaml --yes` para cada perfil mascarado (as permissões foram criadas com `canGet=false`).
4. Credenciais dos usuários novos para o cofre do projeto (skill `vault-factory`); nunca em chat/e-mail.
5. Verificar com `verify-mask` (abaixo) e só então liberar para a aplicação.

### Verificar um usuário mascarado
Objetivo: provar que cada usuário enxerga o que deve.
1. Escolha um valor **fabricado** válido (nunca dado real).
2. Tokenize com o usuário de serviço; detokenize o mesmo token, com o **mesmo tokengroup/template**, com cada usuário do sistema; compare com o esperado (`valor[:L] + máscara*(n-L-R) + valor[n-R:]`; sem máscara = igual ao original).
3. Automatizado: `ctvl.sh verify-mask <amb> --file cfg.yaml --sistema settorj --datatype cns --sample <valor-fabricado>` (as senhas vêm das variáveis `CTVL_<USUARIO>_PASSWORD` do shell do usuário). Por padrão **não imprime os valores**, só tamanhos e posições em claro; `--show-values` mostra (só com valor fabricado).
4. Resultado `DIVERGE` = máscara errada, usuário sem máscara atribuída, ou template diferente na ida/volta.

### Armadilhas medidas (API de dados, em DEV)
- **HTTP 200 também em erro de negócio**: corpo `{"status":"error","reason":...}`. Sempre inspecionar `status == "Succeed"` e a contagem de itens, nunca só o HTTP.
- **Lote máximo 5000 itens** (5000 ok; 5156+ falha com `Could not parse JSON input`, e nesse caso a resposta vem como **objeto**, não lista). Paginar com folga (1000 a 4000). Lista vazia `[]` devolve **1** item de erro.
- **Template igual na ida e na volta.** Template errado com grupo certo: `The requested combination of tokentemplate and tokengroup was not found...`; grupo errado: `The token group specified was not found in the database.`; campo desconhecido no corpo (ex.: `password`) é rejeitado.
- **Falha intermitente** `The requested key name was not found on the key store` (2 em ~10 min em DEV): retry **limitado**. O `verify-mask` já tenta até 2 vezes.
- **O tamanho do token = tamanho da entrada**; entrada com máscara de formatação (`ddd.ddd.ddd-dd`) gera token diferente e maior: **normalizar antes** (só dígitos). Com "All printable ASCII" o alfabeto tem maiúsculas/minúsculas e símbolos (`%`, `_`, `[`, espaço no início/fim): coluna com **collation binária case-sensitive**, escape no `LIKE` e **sem `Trim`**. Com `keep_left=0/keep_right=0` não existe busca por prefixo/sufixo no token.
- O `reason` dos erros termina com `(X-Real-IP '<ip>')`: não logar/expor (a skill mascara).
- O nginx devolve **405** para métodos diferentes de POST na API de dados (`/vts/rest/v2.0/*`); metadados só pela API admin.
- Erros de login/permissão da admin: 401 = JWT inválido (a skill renova uma vez), 403 = o usuário autenticado não administra o vault (não troque por credencial de dados).

## Ao apresentar resultados ao usuário
- Tabelas (operação, tipo, nome, motivo), nunca JSON bruto nem corpos com senha.
- Sempre cite a pendência "HABILITAR DETOKENIZE" (e qualquer `CONFLITO` de máscara) e as marcações "a confirmar" que afetaram o resultado.
- Nunca inclua JWT, senha, host real ou IP. Cite **nomes** de variáveis de ambiente, nunca valores.
- Se `plan` mostrar `CONFLITO`, explique o motivo (tokens existentes ficariam inválidos) e peça decisão; não use `--allow-breaking-update` sem pedido explícito.

## Checklist de revisão (antes de dar uma entrega por pronta)
- [ ] Credencial admin foi fornecida pelo usuário? Nenhuma credencial de dados foi usada na API admin?
- [ ] Nenhum host, IP, senha, token ou hash em arquivo, saída colada ou commit? (`grep -rniE 'eyJ|pbkdf2|password *[:=] *[^<*\s]' .` no que vai ser versionado.)
- [ ] `plan` foi mostrado e entendido antes de `apply --yes`? Nenhuma operação de remoção (a skill não tem)?
- [ ] `api.refs` confirmados com `probe-refs`/evidência, e não presumidos?
- [ ] Charset, chave, LGPD do `keep_left/right` decididos (nenhum `PENDENTE` indevido)?
- [ ] Mesmo template na tokenização e na detokenização? Chave/tokengroup por sistema conforme o isolamento desejado?
- [ ] Máscaras atribuídas aos usuários (o `apply` relê e confere) e `verify-mask` sem `DIVERGE`?
- [ ] Nomes de usuário/máscara na convenção `<sistema>_<datatype>[_<esquema>]` (ou desvios justificados)?
- [ ] Export versionado é o mais recente e sem segredos? Senhas de usuários novos entregues pelo cofre?
- [ ] `tests/run-offline-tests.sh` passa depois de qualquer mudança nos scripts?

## A confirmar (a skill não adivinha; falha com mensagem clara)

| # | Item | Por que está em aberto | Efeito hoje | Como confirmar |
|---|---|---|---|---|
| 1 | **Base path da API admin** no host real | swagger: `basePath /api`; o vault serve a doc em `/vts/admin/v1/` | usa `/api`; configurável em `ADMIN_BASE_PATH` | `ctvl.sh token <amb>` e `admin <amb> GET /masks/` |
| 2 | **Campo do JWT** na resposta do login | swagger só descreve o corpo de entrada (`username/password`) | espera `token`; senão erro listando os **nomes** dos campos recebidos | primeiro `ctvl.sh token <amb>` |
| 3 | **Referências por nome ou por id** na escrita: `tokengroup.key`, `template.tenant/format/charset`, `user.groups`, `perm_user.key`, `perm_group.group/key` | swagger tipa tudo como `string` sem dizer qual. Só `perm_user.user` é provado (pattern de username) | leitura pode usar **evidência** de objetos existentes; **escrita exige** `api.refs.<campo>: name\|id` ou aborta antes de enviar (preflight) | `ctvl.sh probe-refs <amb>`; criar um item de teste na GUI ajuda quando o vault está vazio |
| 4 | **Atribuir máscara a usuário pela API** | **RESOLVIDO para usuário (DEV, 2026-10-08, medido no Swagger UI)**: `PUT /api/users/{id}` com `{"mask": "cns_3_left"}` → 200 `"Mask successfully updated."`; `GET /users/{id}` mostra `"mask": "cns_3_left"`. Valor = NOME da máscara. O `readOnly` do swagger está errado. **Medido em DEV em 2026-10-08 (apply real)**: o `{"mask"}` sozinho só funcionou em usuário **LDAP** (`ldap_user: true`, id 9); em usuário **local** (`ldap_user: false`, id 12) o mesmo PUT devolveu **HTTP 400** `{"username": ["This field is required."], "email": ["This field is required."]}` (estado do cofre intacto). **NÃO medido**: remover a máscara (`null` ou `""`), se **grupo** herda/aceita máscara e **o efeito do PUT sobre a senha** (o `password` NÃO é enviado; conferir com `verify-mask` depois do `apply`) | o `apply` faz read-modify-write mínimo: `GET /users/{id}` e `PUT` com `username` e `email` atuais (só os que o GET devolveu) + `mask`; usuário LDAP: só `{"mask"}`. **Nunca** envia `password`, `id`, `ldap_user`, `is_active`, `is_staff`, `is_superuser` nem `groups`. A premissa de que **campo omitido no PUT não é alterado** vem do DRF (servidor Django/DRF) e é **inferida, NÃO medida**; ela é protegida pela releitura: depois do PUT o `apply` relê e falha fechado (exit 1, nomeando o campo) se a máscara divergir ou se email/is_active/is_staff/is_superuser/groups mudarem em relação ao GET de antes;  máscara diferente = `CONFLITO`; remoção e máscara de grupo NÃO implementadas | medir em usuário/grupo descartáveis: `PUT {"mask": null}` e `""`, e `PUT /groups/{id}` com `mask` |
| 5 | **Barra final** nos paths de detalhe (`/masks/{id}`) | o swagger lista detalhes sem `/` e listas com `/` | sem barra; `api.detail_trailing_slash: true` muda | um `PUT` real e a resposta (301/404 indica a barra) |
| 6 | **`PUT /users/{id}` e o campo `password`** (mantém, apaga ou exige?) | swagger não diz | a skill **não atualiza usuários existentes** (divergência de `ativo`/`grupos` vira `MANUAL`); só cria, e a única escrita em usuário existente é o `PUT` de máscara (`username` e `email` atuais + `mask`, ver nº 4) | teste com usuário descartável |
| 7 | **Permissões**: obrigatoriedade de exatamente um entre `key`/`asymkey`/`opaqueobj`; o que acontece com vários | nenhum é `required` no swagger | **medido em DEV:** o `POST` sem `asymkey` dá 400 (`asymkey: This field is required`); a skill envia `key` com `asymkey`/`opaqueobj` = `null` (formato das linhas existentes). **Confirmado em DEV (2026-10-08):** o `null` é aceito (6 POSTs com HTTP 200; replan = 0 pendente). Grupos: não medido | grupos ainda não medidos |
| 8 | **Granularidade da permissão** (por chave x por tokengroup/template) e o isolamento cpf x cns | swagger só tem `key` | permissões são sobre a chave do sistema; chave compartilhada = permissão compartilhada | equipe do vault |
| 9 | Mapeamentos: `preserve_null_or_1_char`→`copyruntdata`, `allow_small_input`→`allowsmallinput` ("menores que 6 caracteres" no swagger; a pendência do projeto sobre o tamanho mínimo continua aberta) | inferidos pela descrição do swagger | aplicados como descritos | `list templates` num template criado pela GUI |
| 10 | **Nomes dos charsets predefinidos** (`Numeric`, `All printable ASCII` nos relatos do projeto) e o charset dos templates `SINDRAS_*` | decisão do projeto: ASCII imprimível x numérico | `charset: PENDENTE` bloqueia o template | `ctvl.sh list <amb> charsets`; decisão do projeto |
| 11 | **Máscara**: aplicada sobre os dígitos ou sobre o valor formatado; `mask_char` (`*` ou `-`); máscaras "mínimo" (CPF e CNS) | pendências do projeto (`usuarios-e-mascaras.yaml`) | esquemas `a_confirmar` bloqueiam; `--accept-suggestions` aceita a sugestão | equipe do vault e produto |
| 12 | **Criar chave** (`POST /keys/`) gera material criptográfico; política de quem cria e se a `seedkey` pode ser alterada | swagger só tem `name`/`seedkey` | `plan` avisa; `seedkey: true` nunca é enviado sem estar declarado | equipe do vault |
| 13 | **Códigos de sucesso** (201/200/204) e formato de erro 400 do DRF | só o login declara 201 | qualquer 2xx é sucesso; erro mostra o corpo mascarado | primeiro uso |
| 14 | `hml`/`prd`: hosts, CA e se o `/api` é o mesmo | só DEV foi medido | por apelido no arquivo de credenciais | cadastro de cada ambiente |
| 15 | **Soma de permissão grupo + usuário** no CT-VL (o usuário herda o `canGet` do grupo?) | não documentado no swagger nem medido | fail-closed: o `apply` nunca escreve `canGet=true` em grupo com membro mascarado; usuário NOVO mascarado é `BLOQUEADO` se algum grupo dele já tem `canGet=true` no vault; o `enable-detokenize` recusa se algum grupo do usuário tem `canGet=true` | teste com usuário e grupo descartáveis; equipe do vault |

## Arquivos da skill

```
ctvl-api/
  SKILL.md                      este arquivo
  credentials.example           modelo do arquivo de credenciais (sem valores reais)
  scripts/
    ctvl.sh                     CLI único (delega)
    lib-ctvl.sh                 credenciais, token em cache, execução (sourced; prefixo CTVLAPI_)
    ctvl-token.sh ctvl-admin.sh ctvl-list.sh ctvl-export.sh ctvl-plan.sh ctvl-apply.sh
    ctvl-probe-refs.sh ctvl-verify-mask.sh ctvl-setup-env.sh ctvl-envs.sh ctvl-enable-detokenize.sh
    ctvl_core.py + ctvlpy/      motor (HTTP, YAML, plan/apply, export, máscara de saída)
    gen-endpoints.py            regenera references/endpoints.md a partir do swagger
  references/
    swagger.json                swagger da API admin (host trocado por <host>)
                                (conferido contra o servidor DEV em 2026-10-08: mesmos paths e definitions, só o host difere.
                                 Para reconferir: GET https://<host>/vts/admin/v1/doc/swagger/?format=openapi, trocar o host por <host> e comparar;
                                 `mask` só aparece em User, User Group e Mask, sempre readOnly em User/Group (impreciso para User: o PUT aceita, ver "Modelo mental"), e não há PATCH em /users nem /groups)
    endpoints.md                resumo por tag: método, path, finalidade, obrigatórios (gerado)
    schema-config.md            esquema do YAML declarativo, convenção de nomes, herança
    exemplo-config.yaml         defaults + sindras + settorj, sem segredos
  tests/
    run-offline-tests.sh        400+ verificações offline (fixtures + servidor falso em loopback)
    fake_ctvl_server.py  pty_setup_env.py  fixtures/
```

Pré-requisitos: `bash`, `python3` com PyYAML (`python3-pyyaml`). Sem `curl`/`jq` em tempo de uso. Para ter `ctvl` no PATH: `ln -s ~/.claude/skills/ctvl-api/scripts/ctvl.sh ~/.local/bin/ctvl`.
Regerar o resumo de endpoints após atualizar o swagger: `python3 scripts/gen-endpoints.py` (e troque o `host` do swagger por `<host>` antes de gravar em `references/`).

## Cenários de validação do Sindras (`cenarios-sindras/`)

Kit anexo, específico do sistema `sindras` (templates SINDRAS_CPF/SINDRAS_CNS no tokengroup SES), que valida as regras de tokenização contra o cofre DEV com dado SINTÉTICO. Só LÊ/tokeniza; nunca escreve configuração (as escritas continuam só nos subcomandos do `ctvl`). Não altera o comportamento dos comandos `ctvl`. Detalhes e pré-requisitos: `cenarios-sindras/README.md`.

- Rodar (cwd = checkout do Sindras, ou `SINDRAS_ROOT`): `cenarios-sindras/fluxo-dev.sh cenarios --cenario todos`; sem cofre: `... cenarios --offline --cenario todos`; testes: `python3 -m pytest cenarios-sindras -q`.
- C1 normalização/DV/determinismo; C2 round trip e os 4 perfis de máscara; C3 lotes (1/1000/5000, 5156 falha); C4 falha intermitente de key store e retry; C5 isolamento (template/grupo trocado, svc não detokeniza, total não tokeniza); C6 MEDIÇÃO (dígitos em claro, entrada mínima, DV, prefixo).

## Pendências conhecidas (baixas)

Achados baixos da re-revisão, **não corrigidos** nesta rodada (a descrição e a referência `arquivo:linha` do revisor não vieram no briefing; completar ao receber o relatório):

- N4: o plano casa a permissão existente só por usuário e chave, sem excluir as linhas com `asymkey`/`opaqueobj` que o export marca como "ignorados"; um PUT pode perder o `asymkey` (suspeita, não confirmada no servidor). Ref: `scripts/ctvlpy/plan.py` (~346-349) vs `scripts/ctvlpy/export.py` (~33).
- N5: `verify_after` conta as ações PULADAS como pendentes, então `apply --skip-blocked` sem `--no-verify` sai com rc 4; o operador pode se acostumar e deixar de notar divergência real. Ref: `scripts/ctvlpy/plan.py` (~487-491), `scripts/ctvlpy/cli.py` (~234-240).
- N6: `plan --offline` sem `--state-dir`/`--empty-state` chama `client_from_env()`; com `CTVL_CONN_*`/`CTVL_TOKEN_FILE` exportadas no shell, o modo "offline" vai à rede e sem a trava de TLS. Ref: `scripts/lib-ctvl.sh` (~253-256), `scripts/ctvlpy/cli.py` (~66), `scripts/ctvlpy/client.py` (~165-175).
- N7: possível corrida entre a checagem do selo do JWT e o uso do token, que o Python relê a cada request; trocar as credenciais durante uma execução longa pode enviar o token de um host a outro. Suspeita, não reproduzida. Ref: `scripts/lib-ctvl.sh` (~181-192 e ~222-226), `scripts/ctvlpy/client.py` (~75-77).
- N9: permissão escrita à mão com `chave:` vazia/null (sem `tokengroup`) ou com `asymkey` é descartada com um aviso que só traz a contagem, sem nomear qual; uma revogação (`detokenize: false`) pode sumir em silêncio. Ref: `scripts/ctvlpy/config.py` (~363-366 e ~373-375).

As linhas são da revisão e podem ter mudado; localize pelo comportamento.

## Estado da revisão de segurança (2026-10-07)

A skill passou por cinco revisões adversariais. Veredito da última: `apply` APROVADO COM RESSALVAS para hml/prd; `enable-detokenize` REPROVADO para hml/prd. Usar o `enable-detokenize` só em DEV e depois de conferir o `verify-mask` à mão; o runbook é "o `apply` atribui a máscara → `verify-mask` → `enable-detokenize`". Achados abertos da quinta revisão (todos NÃO corrigidos):

1. (alto) verify do enable pode não verificar nada: `pick_users` pega a primeira permissão do usuário; com várias permissões (formato `recursos`/export) a lista fica vazia e o enable imprime "verify ok". Ref: `scripts/ctvlpy/verify.py` (~48, 84-85, 107), `scripts/ctvlpy/enable.py` (~175-176).
2. (alto) a reversão do enable não reverte um `canGet=true` que já existia antes (só percorre o que escreveu na execução). Ref: `enable.py` (~163-169, 179-182).
3. (médio/alto) Ctrl-C/SIGTERM durante o verify não reverte; a reversão usa o mesmo JWT, que pode ter 60 s de vida. Ref: `enable.py` (~164-178, 197-200), `scripts/ctvlpy/client.py` (~113-114), `scripts/lib-ctvl.sh` (~246).
4. (corrigido, resta o aumento) o rebaixamento de `canGet` agora é uma ação separada, escrita mesmo com o ATUALIZAR de `canPost` bloqueado; o que ainda vale é o bloqueio do AUMENTO (`canPost` true) em chave compartilhada sem opt-in. Ref: `scripts/ctvlpy/plan.py` (~484-490).
5. (médio) o `apply` preserva qualquer `canGet=true` existente sem distinguir o do `enable` verificado de um vindo da interface; o plano não avisa. Ref: `plan.py` (~442-443).
6. (médio) a máscara de GRUPO nunca é lida; grupo com máscara no vault recebe `canGet=true`. Ref: `scripts/ctvlpy/state.py` (~179), `plan.py` (~347-376).
7. (baixo) o CPF/CNS de amostra padrão do enable é válido e publicado, e `--sample` em argv fica no histórico do shell. Ref: `enable.py` (~19), `cli.py` (~404).
8. (baixo) máscara declarada que não esconde nada passa no verify. Ref: `verify.py` (~15-16), `config.py` (~118-119).
9. (baixo) o enable não chama `finalize` do plano. Ref: `enable.py` (~38).

Testes que ainda faltam: o mutante `subiu` em ATUALIZAR sobrevive, as asserções de máscara não resolvida passam por acidente e o servidor falso não exige `canGet` na API de dados. As linhas citadas são da revisão e podem ter mudado; localize pelo comportamento.
