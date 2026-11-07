---
name: nuget-factory
description: Workflow genérico de consumo e publicação de pacotes NuGet internos (configurar NuGet.Config, adicionar PackageReference, pack, push, restore) independente do servidor de pacotes. Os comandos concretos do servidor ficam em providers/ — Nexus SES-RJ em providers/nexus/arquivos.md. Use quando o usuário pedir para publicar ou consumir um pacote NuGet interno, configurar fontes de pacotes, ou diagnosticar erros de restore/add package/push contra um feed NuGet.
---

# Skill: nuget-factory

**Tipo:** internal

## Quando executar

- Publicar (`push`) um pacote NuGet interno.
- Consumir/adicionar um pacote NuGet interno num projeto .NET.
- Configurar o `NuGet.Config` de um projeto para apontar para um feed de pacotes.
- Diagnosticar erros de `dotnet add package`/`dotnet restore`/`dotnet nuget push` contra um feed.

## Providers

Os comandos concretos (host, credenciais, repositórios, workarounds de bug) estão em:

- **Nexus SES-RJ** → `providers/nexus/arquivos.md` (ler antes de executar).

Ao adaptar para outro servidor (nuget.org, Azure Artifacts...), manter este fluxo e trocar o provider.

## Princípio de segurança

- **Nunca** peça a senha do feed em texto puro na conversa. Buscar no vault (ver `vault-factory`).
- Ler a senha só por referência com esquema: `NEXUS_PASSWORD_REF` (`op://…`, `pass:…`, `gopass:…`,
  `passbolt:…`, `vault:…#chave`), resolvida por `vault-read` (ver `vault-factory`) e entregue só ao
  processo filho. `NEXUS_PASSBOLT_RESOURCE_ID` ainda é aceita, mas está depreciada.
- **Nunca** gravar a senha em texto claro no `NuGet.Config`. Usar um placeholder de env var
  (ex.: `%NEXUS_NUGET_PASSWORD%`, suportado desde NuGet 4.8+) exportada só dentro do processo que
  roda `dotnet restore`/`add package`/`push`.
- Se precisar baixar segredo adicional do vault para arquivo, gravar só no scratchpad e apagar ao final.

## Fluxo: consumir um pacote interno

1. Gerar o `NuGet.Config` do projeto com a source de consumo (ver provider — ex.: `nexus configure-project`).
2. Adicionar a `PackageReference`. **Evite `dotnet add package --source <nome> --version X`** — há um
   bug conhecido do CLI que trata a source como path local nesse combo (`NU1301: A fonte local
   '<nome>' não existe`). Alternativas que funcionam:
   - `dotnet add package <Nome> --source <nome-da-source>` (sem `--version`, resolve a última), ou
   - editar a `<PackageReference Include="..." Version="..." />` direto no `.csproj`.
3. Restore/build normalmente, exportando a senha só para esse processo (padrão `vault-read` do provider).
4. Se `dotnet add package`/`restore` disser **"Não há versões disponíveis"** mesmo o pacote existindo
   no feed (confirmável via search do provider), **não** assumir permissão/rede — checar primeiro o
   bug de metadados do provider (ex.: Nexus corrompe TFM de `net5.0+` e quebra a auto-seleção de versão).

## Fluxo: publicar (push) um pacote interno

1. Gerar o `NuGet.Config` com a source de publicação (ver provider).
2. **Empacotar mirando `netstandard2.0` quando possível** — evita problemas de resolução para quem
   consumir depois (em feeds que corrompem TFM moderno, ex.: Nexus).
3. `dotnet pack -c Release -o ./nupkgs`
4. Push usando a **source nomeada, sem `--api-key`** se o feed exige Basic Auth real (o header
   `X-NuGet-ApiKey` não funciona em alguns feeds). Ver o comando exato do provider.

## Regra prática transversal

**Sempre especificar a versão explicitamente** (`--version X` ou `<PackageReference Version="X" />`)
ao consumir pacotes internos — nunca deixar o NuGet escolher a última automaticamente. Isso evita
quebra de build por bump não intencional e contorna bugs de auto-seleção em feeds com metadados
corrompidos. É boa prática corporativa independente do provider.
