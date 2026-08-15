---
name: backend-persistence-transactions
description: Use em operações de persistência e fluxos com múltiplas escritas que precisam ser atômicas, aplicando controle transacional no limite correto.
---

# Backend Persistence + Transactions

## Quando usar

Use quando:

- uma operação grava em mais de uma tabela/repositório;
- existe `@Transactional` ou equivalente;
- há risco de atualização parcial;
- persistência precisa ser reorganizada;
- um método mistura leitura, escrita e chamadas externas.

## Objetivo

Garantir que um conjunto de operações de banco que compõe uma única unidade de negócio seja confirmado ou revertido de forma coerente.

## Procedimento

1. Identifique a unidade de negócio que precisa de atomicidade.
2. Posicione a fronteira transacional na camada de aplicação/service apropriada.
3. Inclua apenas operações de banco que realmente pertencem à mesma transação.
4. Evite transações longas envolvendo chamadas HTTP externas.
5. Entenda política de rollback para exceções do framework.
6. Evite `catch` que engole exceção e impede rollback sem intenção explícita.
7. Teste o cenário de falha intermediária.

## Regras

- transação deve representar unidade de consistência, não ser anotação aplicada indiscriminadamente;
- leitura simples não precisa virar transação de escrita por padrão;
- não mantenha lock de banco enquanto espera serviço remoto se puder evitar;
- cada Repository deve permanecer focado em persistência, não em orquestração de negócio.

## Checklist

- [ ] A fronteira transacional está no ponto correto?
- [ ] Todas as escritas necessárias são atômicas?
- [ ] Chamadas externas ficaram fora de transações longas quando possível?
- [ ] Rollback foi validado?
- [ ] Exceções não estão sendo engolidas indevidamente?
