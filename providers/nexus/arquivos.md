# Provider: Nexus Sonatype (SES-RJ)

Detalhes específicos do Nexus SES-RJ usados pela skill `nuget-factory`. Este arquivo é **referência** —
a skill aponta para cá para os comandos concretos.

## Dados do ambiente

- Host: `https://nexus.saude.rj.gov.br`
- Usuário: `<usuário-nexus>`, lido da variável de ambiente `NEXUS_USER` (sem valor padrão no repositório).
- Senha: referida por `NEXUS_PASSWORD_REF=<referência-da-senha>` (qualquer esquema do `vault-read`:
  `op://…`, `pass:…`, `gopass:…`, `passbolt:<id-do-recurso>`, `vault:<mount>/<caminho>#<chave>`).
  Legado, **depreciado**: `NEXUS_PASSBOLT_RESOURCE_ID=<id-do-recurso>` (vira `passbolt://<id>` com aviso).
- Repositórios NuGet relevantes:
  | Nome | Tipo | Uso |
  |---|---|---|
  | `nuget-hosted` | hosted | pacotes internos — **push/deploy** |
  | `nuget.org-proxy` | proxy | espelha nuget.org |
  | `nuget-group` | group | agrega os dois acima — **consumo/restore** |

## Segurança

- **Nunca** pedir a senha em texto puro na conversa. Ler sempre pela referência (`NEXUS_PASSWORD_REF`).
- Ler a senha com `vault-read "$NEXUS_PASSWORD_REF"` e injetar só no processo filho (env) — ver
  `vault-factory` e o provider do cofre escolhido.
- **Nunca** gravar a senha em texto claro no `NuGet.Config`. Usar `%NEXUS_NUGET_PASSWORD%` como
  placeholder (suportado desde NuGet 4.8+) e exportar a env var só dentro do processo que roda
  `dotnet restore`/`add package`/`push`.
- Se precisar baixar segredo adicional do vault para arquivo (`pb import`), gravar só no scratchpad
  da sessão e apagar ao final.

## CLI da skill (`nexus`)

Depois de rodar `nuget-factory/scripts/init.sh` uma vez (symlink em `~/.local/bin/nexus`):

```bash
nexus list-repos                          # lista repositorios (nome, formato, tipo, url)
nexus search <nome> [repositorio]         # busca componentes (default: nuget-group)
nexus delete-component <component-id>     # remove um componente (com confirmacao)
nexus configure-project <dir> [--hosted]  # gera NuGet.Config no projeto
```

`configure-project` gera a source `nexus-ses` (nuget-group, consumo). Com `--hosted`, também gera
`nexus-ses-hosted` (nuget-hosted, push).

## Consumir um pacote interno

1. `nexus configure-project <dir-do-projeto>` — cria o `NuGet.Config` com a source `nexus-ses`.
2. Adicionar a `PackageReference` — **evite `dotnet add package --source <nome> --version X`** (bug
   do CLI que trata a source como path local → `NU1301`). Alternativas que funcionam:
   - `dotnet add package <Nome> --source <nome-da-source>` (sem `--version`, resolve a última), ou
   - editar a `<PackageReference Include="..." Version="..." />` direto no `.csproj`.
3. Restore/build, exportando a senha só para o processo:
   ```bash
   export NEXUS_PASSWORD_REF='<referência-da-senha>'
   NEXUS_NUGET_PASSWORD="$(vault-read "$NEXUS_PASSWORD_REF")" dotnet restore
   ```
4. Se `dotnet add package`/`restore` disser **"Não há versões disponíveis"** mesmo o pacote existindo
   (confirmável via `nexus search <nome>`), ver **Bug de TFM** abaixo antes de assumir permissão/rede.

## Publicar (push) um pacote interno

1. `nexus configure-project <dir-do-projeto> --hosted` — cria também a source `nexus-ses-hosted`.
2. **Empacotar mirando `netstandard2.0`** quando possível (ver Bug de TFM).
3. `dotnet pack -c Release -o ./nupkgs`
4. Push usando a source nomeada, **sem `--api-key`** — o Nexus exige Basic Auth real, não o header
   `X-NuGet-ApiKey`:
   ```bash
   export NEXUS_PASSWORD_REF='<referência-da-senha>'
   NEXUS_NUGET_PASSWORD="$(vault-read "$NEXUS_PASSWORD_REF")" \
     dotnet nuget push nupkgs/<Pacote>.<versao>.nupkg --source nexus-ses-hosted
   ```
   `--api-key "usuario:senha"` ou NuGet API Key da UI **não funciona** (dá `401`) — descoberto
   empiricamente em 2026-08-19.

## ⚠️ Bug de parsing de TargetFramework (Nexus 3.58.1 OSS)

O Nexus corrompe `dependencyGroups[].targetFramework` no feed v3 (`RegistrationsBaseUrl`) para o
moniker moderno unificado (`net5.0` em diante: `net8.0`, `net9.0`, `net10.0`...). O `.nuspec` real
dentro do `.nupkg` fica correto — a corrupção acontece só na re-indexação exposta ao cliente NuGet.

| TFM real no `.nuspec` | `targetFramework` exposto pelo Nexus | Resultado |
|---|---|---|
| `net10.0` | `.NETFramework1.0.0` | `dotnet add package`/`restore` rejeita como incompatível |
| `net8.0` | `.NETFramework8.0` | idem |
| `netstandard2.0` | `.NETStandard2.0` (correto) | resolve normalmente |

**Causa raiz confirmada — bug do Nexus, não configuração** (pesquisado 2026-08-19): issue oficial
[sonatype/nexus-public#831](https://github.com/sonatype/nexus-public/issues/831), label `bug`,
sem PR/fix/milestone. O Nexus remove o separador de ponto do TFM (`net8.0` → `net80`), colidindo com
a sintaxe do .NET Framework clássico. Não há opção de configuração de repositório que afete isso.
Não é questão de versão desatualizada (nossa 3.58.1; mais recente 3.95.1 sem correção).

### Impacto real: só afeta a auto-seleção de versão

| Caminho de resolução | Resultado |
|---|---|
| `dotnet add package <Nome>` **sem** `--version` | ❌ `Não há versões disponíveis do pacote` |
| `dotnet add package <Nome> --version <X.Y.Z>` (explícita, sem `--source` nomeado) | ✅ funciona normal |
| `<PackageReference ... Version="<X.Y.Z>" />` fixado no `.csproj` + `dotnet restore`/`build`/`run` | ✅ resolve e executa |

**Regra prática:** sempre especificar a versão explicitamente — nunca deixar o NuGet escolher a
última. Onde ainda dói: descoberta automática de versão (`add package` sem `--version`, update
automático de dependências, autocomplete de IDEs). Workaround: empacotar mirando `netstandard2.0`
(metadado correto) — só quando a lib não depende de API exclusiva de .NET moderno.

Sintoma a diagnosticar: `error: Não há versões disponíveis do pacote '<Nome>'` mesmo o pacote
existindo e sendo baixável por URL direta. Uma versão com metadado corrompido pode até impedir a
resolução de versões boas do mesmo pacote; remover as versões ruins (`nexus delete-component`)
costuma destravar.

Se o `.csproj` usa `<Nullable>enable</Nullable>`/`ImplicitUsings`, trocar por
`<LangVersion>latest</LangVersion>` ao migrar para `netstandard2.0` (evita `CS8630`).

## Outras armadilhas

- **Acesso anônimo desligado**: `GET` sem credenciais em qualquer repositório retorna `401`. Só a
  listagem de nomes via `/service/rest/v1/repositories` é pública.
- **Lockout temporário de conta**: várias autenticações falhas podem bloquear a conta no LDAP por um
  tempo (sintoma: até `GET`s antes funcionais passam a dar `401`). Login manual na UI destrava.
  Evitar loop de chamadas autenticadas.
- **Controle de acesso é grosso, não por-repositório**: só 3 roles têm privilégios reais (a maioria
  vem de espelhamento LDAP/AD sem privilégio). `nx-admin` = total. Vale checar
  `GET /service/rest/v1/security/roles` periodicamente — encontramos uma role
  `nx-download-artifact-maven-repo` com privilégio `nx-repository-view-*-*-*` (leitura **e escrita**
  em qualquer repositório de qualquer formato). Reportar ao administrador.

## Exemplos de chamadas REST

```bash
export NEXUS_USER='<usuário-nexus>'
export NEXUS_PASSWORD_REF='<referência-da-senha>'
NEXUS_PASSWORD="$(vault-read "$NEXUS_PASSWORD_REF")"   # só dentro de subshell/script, nunca em echo

# Config de um repositorio (writePolicy)
curl -s -K - <<<"user = \"$NEXUS_USER:$NEXUS_PASSWORD\"" \
  "https://nexus.saude.rj.gov.br/service/rest/v1/repositories/nuget/hosted/nuget-hosted"

# Versoes de um pacote no feed v3 (flatcontainer)
curl -s -K - <<<"user = \"$NEXUS_USER:$NEXUS_PASSWORD\"" \
  "https://nexus.saude.rj.gov.br/repository/nuget-group/v3/content/<nome-minusculo>/index.json"

# Metadado de registration (inspecionar o bug de TFM)
curl -s -K - <<<"user = \"$NEXUS_USER:$NEXUS_PASSWORD\"" \
  "https://nexus.saude.rj.gov.br/repository/nuget-group/v3/registration/0/<nome-minusculo>/index.json"
```

Por que `-K -` e não `-u "usuario:senha"`: com `-u`, a senha vai no argv do `curl` e aparece no `ps`.
Com `-K -`, o `curl` lê a configuração (`user = ...`) do stdin. O here-string chega por pipe, não por
argv, e `NEXUS_PASSWORD` fica só no ambiente do shell, vinda de `vault-read`. Limitação: dentro da
sintaxe de configuração do `curl`, `"` e `\` na senha precisam de escape (`\"`, `\\`).

## Expor o comando `nexus` fora da skill

```bash
~/.config/ai/skills/nuget-factory/scripts/init.sh
source ~/.zshrc
```
