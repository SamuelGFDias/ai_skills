---
name: backend-persistence-transactions
description: Use em operações de persistência .NET/EF Core e fluxos com múltiplas escritas que precisam ser atômicas, aplicando DbContext e transações no limite correto.
---

# Backend Persistence + Transactions (.NET)

## Quando usar

Use quando:

- uma operação grava em mais de uma tabela/agregado;
- existe `DbContext`, `SaveChangesAsync`, `BeginTransactionAsync` ou `TransactionScope`;
- há risco de atualização parcial;
- persistência precisa ser reorganizada;
- um método mistura leitura, escrita e chamadas externas;
- é necessário coordenar múltiplos `SaveChanges` como uma unidade atômica.

## Objetivo

Garantir que operações de banco que compõem uma única unidade de negócio sejam confirmadas ou revertidas de forma coerente, respeitando o comportamento transacional do EF Core e do provider utilizado.

## Procedimento

1. Identifique a unidade de negócio que precisa de atomicidade.
2. Verifique se um único `SaveChanges`/`SaveChangesAsync` já oferece a atomicidade necessária antes de criar transação explícita.
3. Quando houver múltiplos `SaveChanges` que precisam ser atômicos, posicione a transação na camada de aplicação/service responsável pela unidade de trabalho.
4. Use `Database.BeginTransactionAsync` ou abstração existente somente quando necessário.
5. Inclua apenas operações de banco pertencentes à mesma unidade de consistência.
6. Evite transações longas envolvendo chamadas HTTP, mensageria ou outros recursos externos.
7. Entenda o comportamento do provider, isolamento e estratégia de retry antes de combinar transação manual com `ExecutionStrategy`.
8. Evite `catch` que engole exceção e deixa estado inconsistente.
9. Propague `CancellationToken` quando disponível.
10. Teste rollback e falha intermediária.

## Regras

- transação deve representar unidade de consistência, não ser aplicada indiscriminadamente;
- um único `SaveChanges` do EF Core já é transacional para providers relacionais compatíveis, salvo comportamento específico do provider;
- leitura simples não precisa de transação explícita por padrão;
- não mantenha locks de banco enquanto aguarda serviço remoto se puder evitar;
- não compartilhe `DbContext` entre threads;
- respeite lifetime `Scoped` do `DbContext` em aplicações ASP.NET Core;
- Repository, quando existir, deve permanecer focado em persistência, não em orquestração de negócio;
- não crie migration ou altere schema apenas para contornar erro de código.

## Checklist

- [ ] Um único `SaveChangesAsync` já resolveria a atomicidade?
- [ ] A fronteira transacional está no ponto correto?
- [ ] Todas as escritas necessárias são atômicas?
- [ ] Chamadas externas ficaram fora de transações longas quando possível?
- [ ] Lifetime e uso do `DbContext` estão corretos?
- [ ] Retry/ExecutionStrategy foi considerado quando aplicável?
- [ ] Rollback foi validado?
- [ ] Exceções não estão sendo engolidas indevidamente?
