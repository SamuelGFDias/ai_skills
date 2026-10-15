---
name: dotnet-project-rename
description: Checklist para renomear um projeto .NET (diretório, .csproj, namespace raiz, sln, Dockerfile) sem quebrar o build — inclui limpar diretórios-fantasma de tentativas anteriores e qualificar referências de namespace parcialmente qualificadas (CS0246). Use ao renomear projeto/namespace raiz de uma solution .NET, ou ao corrigir CS0246 logo após um rename.
---

# Skill: dotnet-project-rename

**Tipo:** open-source

Exemplo usado abaixo: `Empresa.Antigo` -> `Empresa.Novo`. Substituir pelos nomes reais, respeitando a caixa exata desejada.

## Passos

### 1. Limpar diretórios-fantasma antes de mover

Listar o diretório-pai e procurar variantes de caixa do **destino** (`Empresa.Novo`, `empresa.novo`, `EMPRESA.NOVO`):

```bash
ls -la src/
git status --short --ignored src/
```

Remover somente os que contêm apenas `bin/`/`obj/` (artefatos de uma tentativa anterior revertida). Por quê: ficam ocultos pelo `.gitignore`, enganam a inspeção e conflitam com o `git mv`, principalmente em sistemas de arquivos que diferenciam caixa. Se houver qualquer arquivo versionado ou não ignorado, parar e investigar.

### 2. Mover com git

```bash
git mv src/Empresa.Antigo src/Empresa.Novo
git mv src/Empresa.Novo/Empresa.Antigo.csproj src/Empresa.Novo/Empresa.Novo.csproj
```

`git mv` preserva o histórico. Em mudança só de caixa, usar um nome intermediário.

### 3. Replace global do nome antigo

O mesmo texto aparece em vários lugares; substituir em todos:

- `namespace`/`using` nos `.cs`;
- caminhos em `.sln`/`.slnx`, `.csproj` (`ProjectReference`), `Directory.Build.props`;
- `RootNamespace`/`AssemblyName` e nome de serviço/configuração;
- pipelines CI/CD, `docker-compose` e `Dockerfile` (`COPY`, `dotnet publish`, `ENTRYPOINT ["dotnet", "Empresa.Antigo.dll"]`).

```bash
grep -rIl "Empresa.Antigo" --exclude-dir={.git,bin,obj,node_modules} .
```

Conferir o diff inteiro; um replace cego também atinge texto que não deveria mudar (documentação histórica, strings de dados).

### 4. Qualificar referências parcialmente qualificadas (obrigatório)

Referências como `Application.DTOs.Exame.CriarDto` só compilavam porque, subindo do namespace antigo (`Empresa.Antigo.Validators`), o compilador alcançava `Empresa.Application...`. Com o novo namespace raiz essa subida não existe e o build falha com **CS0246**.

```bash
grep -rnE "(^|[^.A-Za-z])(Application|Infrastructure|Domain)\.[A-Z]" --include=*.cs src/ tests/
```

Para cada ocorrência sem prefixo da empresa, qualificar por completo (`Empresa.Application.DTOs...`) ou adicionar `using`. Ajustar o padrão aos nomes de camada do repo.

### 5. Build e testes

```bash
dotnet build
dotnet test
```

Build limpo (`dotnet clean` ou apagar `bin/obj`) para não mascarar erros com artefatos antigos. Se o build passar mas a imagem Docker falhar, rever a DLL no `Dockerfile` e o nome do serviço.

## Checklist

- [ ] Diretório-pai listado e fantasmas de caixa removidos (só `bin/obj` ignorados)?
- [ ] Diretório e `.csproj` movidos com `git mv`?
- [ ] Replace global feito e diff revisado (namespace, sln, csproj, serviço, Dockerfile, CI)?
- [ ] grep por `Application.`/`Infrastructure.`/`Domain.` sem prefixo executado e ocorrências qualificadas?
- [ ] `dotnet build` e `dotnet test` verdes a partir de build limpo?
