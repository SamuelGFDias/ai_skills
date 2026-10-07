# Esquema do arquivo de configuração declarativa (versão 1)

Arquivo YAML lido por `plan`, `apply`, `check-config`, `verify-mask` e gerado por `export`. É a fonte do que existe (ou deve
existir) no vault. Pode ser versionado com o projeto: **não contém senhas, tokens, hashes nem ids**.
Exemplo completo: `references/exemplo-config.yaml`.

## Duas formas de escrever (combináveis)

| Forma | Quando usar | Chaves |
|---|---|---|
| **Autoria** | escrever a configuração de sistemas (`sindras`, `biae`, `settorj`) herdando padrões | `defaults`, `sistemas`, `usuarios_padrao`, `convencao`, `api` |
| **Plana** (`recursos`) | o que o `export` gera; objetos explícitos, um a um | `recursos.*` |

As duas viram o mesmo modelo interno. O mesmo nome definido duas vezes com conteúdo diferente é erro (nada é sobrescrito em silêncio).

## Convenção de nomes

`<sistema>_<datatype>[_<esquema>]`, só `[a-z0-9_]` em minúsculas.

| Exemplo | sistema | datatype | esquema | Leitura |
|---|---|---|---|---|
| `sindras_cns` | sindras | cns | (nenhum) | genérico/padrão, **para testes** |
| `settorj_cns` | settorj | cns | (nenhum) | com a configuração própria do sistema |
| `sindras_cpf_3_left_2_right` | sindras | cpf | `3_left_2_right` | usuário com máscara 3 à esquerda e 2 à direita |
| `sindras_svc_tokenize` | sindras | `svc` (reservado) | `tokenize` | usuário de serviço (só tokeniza) |
| `cns_3_left` | (máscara) | cns | `3_left` | **máscara** padrão: `<datatype>_<esquema>` |
| `settorj_cns_3_left` | settorj | cns | `3_left` | máscara específica do settorj (sobrescreveu o padrão) |

- `sindras_*` é o conjunto **genérico de teste**. O ideal é cada sistema ter a sua configuração (`settorj_*`, `biae_*`).
- Sistema e datatype precisam estar em `convencao.sistemas` / `convencao.datatypes` (padrão: `sindras, biae, settorj` e `cpf, cns`).
- **Nome fora do padrão não é ignorado**: `names`, `list users` e `export` o reportam (`fora_do_padrao`); no modo `--docs-dir` os
  usuários `ctvl_*` aparecem como aviso, mas continuam gerenciáveis pelo nome que têm.
- Template: `<SISTEMA>_<DATATYPE>` em maiúsculas (ex.: `SETTORJ_CNS`); tokengroup: `<SISTEMA>`. Ambos sobrescrevíveis (`template.nome`, `tokengroup`).
- Senha de usuário novo: `password_ref: env:CTVL_<USUARIO_EM_MAIÚSCULAS>_PASSWORD` (padrão derivado; ex.: `CTVL_SETTORJ_CNS_PASSWORD`). Um `password_ref` explícito só é aceito se o nome casar `^CTVL_[A-Z0-9_]+_PASSWORD$`; `CTVL_ADMIN_PASSWORD*` (senha admin) e `CTVL_LOGIN_*` são recusados com erro, assim como qualquer outro nome (`env:HOME`). O `plan` mostra o nome da variável de cada usuário a criar. Se o nome derivado for proibido (usuário `admin`), o arquivo carrega, mas a CRIAÇÃO desse usuário fica `BLOQUEADO`.

## Autoria: `defaults` + `sistemas`

```yaml
versao: 1
convencao: {sistemas: [sindras, biae, settorj], datatypes: [cpf, cns]}
api: {refs: {}, detail_trailing_slash: false}
usuarios_padrao: {email_dominio: example.invalid, ativo: true}   # e-mail é obrigatório na API
recursos: {chaves: [{nome: SINDRAS_KEY}], grupos: [{nome: app_x}]}  # infraestrutura compartilhada

defaults:
  datatypes:
    <datatype>:
      template: {format, charset, keep_left, keep_right, irreversible, allow_small_input, preserve_null_or_1_char, prefix}
      mascaras: {<esquema>: {show_left, show_right, mask_char, status?} | null}   # null = sem máscara
      usuarios:
        - {esquema: <esquema>|null, permissoes: [tokenize, detokenize], mascara?: <esquema>|null, grupos?: [..], email?, ativo?, password_ref?, nome?}
  servico:                       # usuários de serviço (datatype reservado svc)
    - {esquema: tokenize, permissoes: [tokenize]}

sistemas:
  <sistema>:
    tokengroup: <nome>           # padrão: SISTEMA em maiúsculas
    chave: <nome da chave>       # obrigatório para criar o tokengroup (permissões são sobre a CHAVE)
    chave_compartilhada: false   # opt-in: true permite usar uma chave que OUTRO tokengroup já usa (ver abaixo)
    datatypes: [..]              # padrão: todos os de defaults.datatypes
    servico: [..]                # substitui defaults.servico
    overrides:
      <datatype>:
        template: {campo: valor} # mescla campo a campo sobre defaults
        mascaras: {<esquema>: {...} | null}   # mescla por esquema
        usuarios: [..]           # SUBSTITUI a lista herdada
        usuarios_extra: [..]     # ACRESCENTA à lista herdada
```

Regras de herança:
- `template`: mescla campo a campo (o do sistema vence). O `tokengroup` do template é sempre o do sistema.
- `mascaras`: mescla por esquema. Se o sistema muda os parâmetros de um esquema, nasce uma máscara própria `<sistema>_<datatype>_<esquema>`;
  se não muda, usa a padrão `<datatype>_<esquema>` (sem duplicar). Mesmo nome com parâmetros diferentes é erro.
- `usuarios`: cada entrada gera o usuário `<sistema>_<datatype>[_<esquema>]` (ou `nome:` explícito, que precisa casar com sistema/datatype/esquema).
  A máscara do usuário é a do esquema de mesmo nome no catálogo (se existir), ou `mascara:` explícito; `null`/ausente = **sem máscara = vê o dado completo**.
- `permissoes: [tokenize, detokenize]` vira `canPost`/`canGet` na chave do sistema.

### Campos do template (e campo da API)

| YAML | API (`/tokentemplates/`) | Observação |
|---|---|---|
| `nome` | `name` | |
| `tokengroup` | `tenant` | referência (nome x id a confirmar) |
| `format` | `format` | ex.: `FPE`; referência |
| `charset` | `charset` | `PENDENTE`/vazio **bloqueia** o item; referência |
| `keep_left` / `keep_right` | `keepleft` / `keepright` | padrão 0 |
| `irreversible` | `irreversible` | padrão false |
| `allow_small_input` (alias `allow_small_inputs`) | `allowsmallinput` | swagger: "inputs smaller than 6 characters" |
| `preserve_null_or_1_char` | `copyruntdata` | mapeamento por descrição do swagger; a confirmar |
| `prefix` | `prefix` | padrão "" |
| `start_year`, `end_year`, `date_record_count`, `date_table_num` | `startyear`, `endyear`, `daterecordcount`, `datetablenum` | só se declarados |

### Máscara

| YAML (alias) | API (`/masks/`) |
|---|---|
| `show_left` (`keep_left`) | `showleft` |
| `show_right` (`keep_right`) | `showright` |
| `mask_char` | `maskchar` |
| `status: a_confirmar` / `SUGESTAO_A_CONFIRMAR` | bloqueia o item até decisão (ou `--accept-suggestions`) |

## Forma plana: `recursos`

Listas (todas opcionais): `chaves`, `charsets`, `grupos`, `mascaras`, `tokengroups`, `templates`, `usuarios`,
`permissoes_usuarios`, `permissoes_grupos`. Cada item usa os mesmos campos acima. Particularidades:

- `chaves: [{nome, seedkey?}]`: criar uma chave gera material no cofre; combine com a equipe do vault. Nunca marque `seedkey: true` sem decisão explícita.
- `charsets`: só os **customizados** (`alphabet` obrigatório; `range` true/false). Os predefinidos (ex.: `Numeric`) são só referenciados por nome; o export os lista em `charsets_predefinidos` (informativo).
- `tokengroups: [{nome, chave, chave_compartilhada?}]`. **Chave compartilhada:** permissão de token é por CHAVE, então um tokengroup que reutiliza a chave de outro dá, a quem tem permissão nele, acesso aos tokens do outro sistema. Por isso o `plan` deixa BLOQUEADO o tokengroup a criar cuja chave já é usada por outro tokengroup do vault **ou declarado no mesmo arquivo** (ex.: dois sistemas com a mesma chave num vault vazio), e a permissão (e o usuário só dela) que o YAML pede para criar/atualizar sobre essa chave, mesmo com o tokengroup já existente no vault. O compartilhamento que já existe no vault não é bloqueado (permissão que já existe segue `OK`). Só o que AUMENTA privilégio é bloqueado (criar com flag `true`, ou subir uma flag): rebaixar nunca é bloqueado. Permissão só por `chave` (formato do export, sem `tokengroup`) em chave usada por mais de um tokengroup (vault ou arquivo) sem opt-in em todos também é bloqueada ao aumentar privilégio. Uma permissão que declara `tokengroup` e `chave` diferente da chave declarada para ele fica `BLOQUEADO`. Cada tokengroup que compartilha precisa do opt-in. O opt-in é explícito e nomeado: `chave_compartilhada: true` (no sistema, na autoria, ou no item de `tokengroups`). Só use com decisão da equipe do vault.
- `usuarios: [{nome, email, ativo, grupos, mascara, password_ref?}]`. `mascara` = **nome** da máscara. Campos informativos `convencao_nome` e `fora_do_padrao` são aceitos e ignorados.
- `permissoes_usuarios: [{usuario, chave, tokenize, detokenize}]` (ou `tokengroup:` no lugar de `chave:` para resolver a chave do tokengroup). Com `tokengroup:` declarado, a permissão **depende** do tokengroup e, se a `chave` diferir da chave atual desse tokengroup no vault, fica `BLOQUEADO`.
- `permissoes_grupos: [{grupo, chave, tokenize, detokenize}]`.
- **Perfil mascarado (regra única):** usuário com `mascara` declarada ou com máscara atribuída no vault é "mascarado". Para ele o `apply` NUNCA escreve `canGet=true`: a permissão é criada/ajustada com `canGet=false` (`canPost` como declarado), em qualquer estado da máscara (confirmada, `a_confirmar`, bloqueada, divergente, referência `user.mask` que não resolve), inclusive rebaixando um `true`. Só preserva um `true` já existente quando a máscara atribuída é exatamente a declarada e igual no vault (o que o `enable-detokenize` deixou). O único caminho que escreve `true` é `ctvl enable-detokenize <amb> <usuario> --file CFG [--yes]` (pré-condições a-f e verify-mask com reversão, ver SKILL.md). O `plan`/resumo do `apply` listam "HABILITAR DETOKENIZE pendente" uma vez por usuário. **Grupos:** permissão de grupo com `detokenize` declarado é escrita com `canGet=false` se algum membro (no vault ou declarado em `usuarios[].grupos`) for mascarado, e o plano lista o grupo e os membros. Usuário NOVO mascarado em grupo que já tem `canGet=true` no vault fica `BLOQUEADO` (soma grupo+usuário não confirmada).
- Permissão com `tokengroup:` existente no vault: a chave efetiva (declarada na permissão, declarada/herdada do tokengroup no arquivo) é SEMPRE comparada com a chave real do tokengroup; se diferir, ou se o formato da referência `tokengroup.key` não é comparável (evidência inconclusiva e sem `api.refs.tokengroup.key`), a permissão fica `BLOQUEADO`. A dependência do tokengroup (`BLOQUEADO`/`CONFLITO` leva a permissão junto) continua valendo.
- `ignorados: {permissoes_usuarios: [...], permissoes_grupos: [...]}`: seção **informativa** gerada pelo `export` com as permissões que a skill não gerencia (sem `chave`, ou sobre `asymkey`/`opaqueobj`), ordenadas por usuário/grupo, chave, asymkey, opaqueobj. O loader a ignora com um aviso curto (`recursos.ignorados: N permissão(ões)...`); não vão para `plan`/`apply`. Entradas desse tipo em `permissoes_*` (formato antigo do export: `chave: null` sem `tokengroup`, ou com `asymkey`/`opaqueobj`) também são ignoradas com aviso; escrever `permissoes_*` à mão sem `chave` nem `tokengroup` continua sendo erro.

## `api`

| Campo | Efeito |
|---|---|
| `api.refs.<campo>: name\|id` | **Confirma** como a API recebe/devolve a referência. Sem isso a ESCRITA falha antes de qualquer chamada. Campos: `tokengroup.key`, `template.tenant`, `template.format`, `template.charset`, `user.groups`, `perm_user.key`, `perm_group.group`, `perm_group.key` (`perm_user.user` é nome, provado pelo pattern de username no swagger; `user.mask` é só leitura) |
| `api.detail_trailing_slash` | `true` acrescenta `/` nos paths de detalhe (`/masks/{id}/`); o swagger os lista sem barra (a confirmar) |

A **leitura** (plan/list/export) pode usar evidência: se todos os valores observados num campo batem com nomes (ou ids) de objetos existentes, o modo é
inferido e anotado em `api.refs_observadas` do export, que **não** vale como confirmação para escrita.

## O que o `export` garante

- Lista branca de campos por recurso: nada de ids internos, hash de senha, `is_superuser`/`is_staff`, sessões, IPs ou tokens.
- Determinismo: listas ordenadas por nome, grupos de usuário ordenados, sem data/hora; duas execuções sobre o mesmo estado dão bytes idênticos.
- Verificação final: o texto é varrido por JWT, hash de senha, `Bearer`, IPv4 e campos `password:`/`secret:`; achado = aborta sem gravar.
- Só permissões sobre **chave** saem como itens aplicáveis. As sem chave ou sobre `asymkey`/`opaqueobj` vão para `recursos.ignorados` (informativo), de modo que o arquivo exportado seja aceito de volta por `check-config`/`plan`/`apply` (round-trip idempotente, testado).

## Semântica de `plan` / `apply`

| Operação | Significado | `apply` |
|---|---|---|
| `OK` | já existe e confere | nada |
| `CRIAR` | não existe | `POST` |
| `ATUALIZAR` | máscara com parâmetros diferentes; permissão com flags diferentes; template só com `--allow-breaking-update` | `PUT` |
| `CONFLITO` | muda a receita de um template existente ou a chave de um tokengroup/charset/chave (tokens existentes ficam inválidos) | não aplica (exige flag explícita só para template) |
| `MANUAL` | usuário existente difere (grupos/ativo/máscara) ou máscara a atribuir a usuário | **nunca** aplica: `mask` é somente leitura no swagger e o `PUT /users/{id}` é a confirmar |
| `BLOQUEADO` | conteúdo pendente (charset `PENDENTE`, máscara `a_confirmar`, chave não declarada, e-mail ausente, dependência inexistente, permissão sobre chave diferente da do tokengroup) | aborta tudo, ou pula com `--skip-blocked`; os dependentes também são pulados: templates do tokengroup, permissões que declaram esse `tokengroup` e o usuário a criar cujas permissões foram todas bloqueadas/puladas |

Ordem: chaves, charsets, grupos, tokengroups, templates, máscaras, usuários, permissões de usuário, permissões de grupo.
Nunca deleta. Objetos que estão no vault e fora do arquivo aparecem em `--show-extra` e permanecem.
`apply` repete o plano depois de aplicar e informa quantas ações ainda faltam (esperado 0).
