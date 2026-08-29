---
name: replatforms
description: Prompt de papel completo para engenheiro sênior de modernização de sistemas legados Delphi 7 para .NET + Angular, com Firebird 2.5 como fonte de verdade. Cobre análise de forms, extração de regras de negócio, compatibilidade SQL/PSQL Firebird, EF Core, coexistência Delphi+.NET e testes de caracterização. Use quando o usuário pedir para migrar, modernizar, portar ou analisar um sistema Delphi 7 (Object Pascal/Firebird 2.5) para .NET/ASP.NET Core + Angular.
---

# Skill: replatforms

**Tipo:** internal

## Quando executar

- Migrar, modernizar, portar ou analisar uma aplicação **Delphi 7** (Object Pascal + Firebird 2.5)
  para arquitetura moderna **ASP.NET Core + Angular**.
- Engenharia reversa de forms Delphi e extração de regras de negócio.
- Trabalho que envolva compatibilidade SQL/PSQL Firebird 2.5, EF Core + Firebird, ou coexistência
  de Delphi e .NET durante a migração.

## Como usar

1. **Ler o prompt completo antes de começar:** `docs/refactor-delphi7-2-dotnet.md` — define o papel
   (engenheiro sênior), a hierarquia de fontes de verdade (aplicação Delphi + banco Firebird em
   produção mandam), as especializações (Firebird 2.5 SQL/PSQL, Delphi 7, EF Core, Angular) e o
   formato de resposta esperado durante a migração.
2. O prompt é a **configuração de papel** (system/role prompt) para a sessão de migração — deve ser
   lido integralmente, não resumido.
3. Durante a migração, seguir as seções na ordem do prompt:
   - Análise de forms → investigação de funcionalidade → extração de regras → classificação.
   - Migração → especificação (Planejamento, Specs e Issues) → testes de caracterização → code review.

## Fonte de verdade (regra fundamental)

- A aplicação Delphi existente e o banco Firebird 2.5 em produção são as fontes de verdade para o
  comportamento atual do sistema.
- Regras de negócio, comportamento funcional, integridade de dados, semântica transacional e
  rastreabilidade entre código antigo e novo devem ser preservados fielmente.
