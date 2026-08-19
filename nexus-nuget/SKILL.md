---
name: nexus-nuget
description: Acessa a API REST do Nexus Sonatype da SES-RJ (https://nexus.saude.rj.gov.br), lista repositorios, publica (push) e consome pacotes NuGet internos, e configura projetos .NET (NuGet.Config) para apontar para o Nexus. Credenciais vem do Passbolt (vault "Nexus"), nunca digitadas em texto puro na conversa. Inclui workaround para um bug de parsing de TargetFramework do Nexus com pacotes net5.0+. Use quando o usuario pedir para acessar o Nexus, listar repositorios, publicar/consumir pacotes NuGet internos, ou configurar um projeto para usar o Nexus como fonte de pacotes.
---

# Skill: nexus-nuget

## Quando executar

- Pedidos para acessar/consultar a API do Nexus Sonatype da SES-RJ.
- Publicar (`push`) um pacote NuGet interno no Nexus.
- Consumir/adicionar um pacote NuGet interno num projeto .NET.
- Configurar o `NuGet.Config` de um projeto para apontar para o Nexus.
- Diagnosticar erros de `dotnet add package`/`dotnet restore`/`dotnet nuget push` contra o Nexus.

## Dados do ambiente

- Host: `https://nexus.saude.rj.gov.br`
- Usuário: `samuel.dias`
- Senha: vault **"Nexus"** no Passbolt (recurso `3ccc4fa5-4c5c-47b9-aa21-735f5cd9a89d`)
- Repositórios NuGet relevantes:
  | Nome | Tipo | Uso |
  |---|---|---|
  | `nuget-hosted` | hosted | pacotes internos — **push/deploy** |
  | `nuget.org-proxy` | proxy | espelha nuget.org |
  | `nuget-group` | group | agrega os dois acima — **consumo/restore** |

## Princípio de segurança

- **Nunca peça a senha em texto puro na conversa.** Buscar sempre no Passbolt (vault "Nexus").
- Ler a senha só via `passbolt exec -- <comando>` (injeta a variável de ambiente só no processo
  filho, nunca no shell interativo/histórico) — ver `scripts/lib.sh:nexus_exec`.
- **Nunca gravar a senha em texto claro no `NuGet.Config`.** Usar sempre
  `%NEXUS_NUGET_PASSWORD%` como placeholder (suportado desde NuGet 4.8+) e exportar essa env var
  só dentro do processo que roda `dotnet restore`/`add package`/`push`, via `passbolt exec`.
- Se precisar baixar algum segredo adicional do vault para arquivo (`pb import`), gravar só no
  scratchpad da sessão e apagar o arquivo ao final do trabalho.

## CLI da skill

Depois de rodar `scripts/init.sh` uma vez (symlink em `~/.local/bin/nexus`, já no PATH):

```bash
nexus list-repos                          # lista repositorios (nome, formato, tipo, url)
nexus search <nome> [repositorio]         # busca componentes (default: nuget-group)
nexus delete-component <component-id>     # remove um componente (com confirmacao)
nexus configure-project <dir> [--hosted]  # gera NuGet.Config no projeto
```

`configure-project` gera a source `nexus-ses` (nuget-group, para consumo). Com `--hosted`, também
gera `nexus-ses-hosted` (nuget-hosted, para push).

## Fluxo: consumir um pacote interno num projeto .NET

1. `nexus configure-project <dir-do-projeto>` — cria o `NuGet.Config` com a source `nexus-ses`.
2. Adicionar a `PackageReference` — **evite `dotnet add package --source <nome> --version X`**,
   há um bug conhecido do CLI que trata o nome da source como path local nesse combo
   (`NU1301: A fonte local '<nome>' não existe`). Duas alternativas que funcionam:
   - `dotnet add package <Nome> --source <nome-da-source>` (sem `--version`, resolve a última) ou
   - editar a `<PackageReference Include="..." Version="..." />` direto no `.csproj`.
3. Restore/build normalmente, exportando a senha só para esse processo:
   ```bash
   export NEXUS_PASSWORD=passbolt://3ccc4fa5-4c5c-47b9-aa21-735f5cd9a89d
   passbolt exec -- bash -c 'export NEXUS_NUGET_PASSWORD="$NEXUS_PASSWORD"; dotnet restore'
   ```
4. Se `dotnet add package`/`restore` disser **"Não há versões disponíveis"** mesmo o pacote
   existindo no Nexus (confirmável via `nexus search <nome>`), ver a seção **Bug de TFM** abaixo
   antes de assumir problema de permissão/rede.

## Fluxo: publicar (push) um pacote interno

1. `nexus configure-project <dir-do-projeto> --hosted` — cria também a source `nexus-ses-hosted`.
2. **Empacotar mirando `netstandard2.0`** quando possível (ver Bug de TFM) — evita problemas de
   resolução para quem for consumir depois.
3. `dotnet pack -c Release -o ./nupkgs`
4. Push **usando a source nomeada, sem `--api-key`** — o Nexus exige Basic Auth real, não o header
   `X-NuGet-ApiKey`:
   ```bash
   export NEXUS_PASSWORD=passbolt://3ccc4fa5-4c5c-47b9-aa21-735f5cd9a89d
   passbolt exec -- bash -c 'export NEXUS_NUGET_PASSWORD="$NEXUS_PASSWORD"; \
     dotnet nuget push nupkgs/<Pacote>.<versao>.nupkg --source nexus-ses-hosted'
   ```
   Usar `--api-key "usuario:senha"` ou uma NuGet API Key gerada na UI **não funciona** nesta
   instância (dá `401`) — descoberto empiricamente em 2026-08-19.

## ⚠️ Bug de parsing de TargetFramework (Nexus 3.58.1 OSS)

Descoberto em 2026-08-19: o Nexus corrompe o campo `dependencyGroups[].targetFramework` no feed
v3 (`RegistrationsBaseUrl`) para pacotes com o **moniker moderno unificado** (`net5.0` em diante:
`net8.0`, `net9.0`, `net10.0`...). O `.nuspec` real dentro do `.nupkg` fica correto — a corrupção
acontece só na re-indexação que o Nexus expõe ao cliente NuGet.

Exemplos observados:

| TFM real no `.nuspec` | `targetFramework` exposto pelo Nexus | Resultado |
|---|---|---|
| `net10.0` | `.NETFramework1.0.0` | `dotnet add package`/`restore` rejeita como incompatível |
| `net8.0` | `.NETFramework8.0` | idem |
| `netstandard2.0` | `.NETStandard2.0` (correto) | resolve normalmente |

Sintoma no cliente: `error: Não há versões disponíveis do pacote '<Nome>'`, mesmo o pacote
existindo e sendo baixável por URL direta (`GET .../v3/content/<nome>/<versao>/<nome>.<versao>.nupkg`
funciona). Uma versão com metadado corrompido no histórico pode até impedir a resolução de versões
boas do mesmo pacote — se isso acontecer, remover as versões ruins (`nexus delete-component`)
costuma destravar.

**Causa raiz confirmada — é bug do Nexus, não configuração nossa** (pesquisado em 2026-08-19):
issue oficial [sonatype/nexus-public#831](https://github.com/sonatype/nexus-public/issues/831),
label `bug`, aberta em 2025-11-27, **sem PR/fix/milestone até hoje**. O Nexus remove o separador de
ponto do TFM ao gerar os metadados NuGet (v2 e v3) — `net8.0` vira `net80`, `net10.0` vira `net100`
— e esse formato sem ponto colide com a sintaxe antiga do .NET Framework clássico, fazendo
`NuGet.Protocol`/`dotnet`/Rider interpretarem errado. Não existe nenhuma opção de configuração de
repositório (protocolo v2/v3, cache, content-type) que afete isso — é hardcoded no parser interno
do Nexus.

**Não é questão de versão desatualizada**: nossa instância roda 3.58.1; a mais recente é 3.95.1
(13/ago/2026). Revisão das release notes de todas as versões 2026 não encontrou nenhum fix
relacionado a esse bug — mesmo atualizando o Nexus, o problema provavelmente persiste.

**Workaround recomendado**: empacotar bibliotecas internas (`classlib`) mirando `netstandard2.0`
em vez de `net8.0`/`net9.0`/`net10.0`. `netstandard2.0` é consumível por qualquer projeto
`net5.0+` e o Nexus expõe o metadado corretamente (não colide com a sintaxe do .NET Framework). Se
a lib precisa de APIs exclusivas de .NET moderno (não disponíveis em `netstandard2.0`), a saída é
acompanhar a issue #831 upstream — não há workaround de configuração para esses casos.

Se o `.csproj` usa `<Nullable>enable</Nullable>`/`ImplicitUsings`, trocar por
`<LangVersion>latest</LangVersion>` ao migrar para `netstandard2.0` (evita `CS8630` — `netstandard2.0`
usa C# 7.3 por padrão).

## Outras armadilhas encontradas

- **Acesso anônimo desligado**: `GET` sem credenciais em qualquer repositório (`nuget-group`,
  `nuget-hosted`) retorna `401`. Só a listagem de nomes de repositórios via
  `/service/rest/v1/repositories` é pública. Consumo de pacotes sempre exige autenticação.
- **Lockout temporário de conta**: várias tentativas de autenticação falha (ex.: testando um token
  errado repetidamente) podem bloquear a conta no LDAP por um tempo — sintoma: até `GET`s que
  antes funcionavam passam a dar `401`. Login manual bem-sucedido na UI do Nexus destrava. Evitar
  repetir chamadas autenticadas em loop quando isso acontecer.
- **Controle de acesso é grosso, não por-repositório**: só 3 roles do Nexus têm privilégios reais
  (a maioria das roles listadas vem de espelhamento LDAP/AD sem privilégio nenhum atribuído no
  Nexus). `nx-admin` = acesso total. Vale checar
  `GET /service/rest/v1/security/roles` (autenticado) periodicamente — encontramos uma role
  chamada `nx-download-artifact-maven-repo` com privilégio `nx-repository-view-*-*-*` (leitura
  **e escrita** em qualquer repositório de qualquer formato, não só Maven como o nome sugere).
  Vale reportar para quem administra o Nexus.

## Exemplos de chamadas REST úteis

```bash
export NEXUS_PASSWORD=passbolt://3ccc4fa5-4c5c-47b9-aa21-735f5cd9a89d

# Config de um repositorio (inclui writePolicy: ALLOW / ALLOW_ONCE / DENY)
passbolt exec -- bash -c 'curl -s -u "samuel.dias:$NEXUS_PASSWORD" \
  "https://nexus.saude.rj.gov.br/service/rest/v1/repositories/nuget/hosted/nuget-hosted"'

# Versoes de um pacote no feed v3 (flatcontainer)
passbolt exec -- bash -c 'curl -s -u "samuel.dias:$NEXUS_PASSWORD" \
  "https://nexus.saude.rj.gov.br/repository/nuget-group/v3/content/<nome-minusculo>/index.json"'

# Metadado de registration (para inspecionar o bug de TFM)
passbolt exec -- bash -c 'curl -s -u "samuel.dias:$NEXUS_PASSWORD" \
  "https://nexus.saude.rj.gov.br/repository/nuget-group/v3/registration/0/<nome-minusculo>/index.json"'
```

## Disponibilizar o comando `nexus` fora da skill

```bash
~/.claude/skills/nexus-nuget/scripts/init.sh
source ~/.zshrc
```
