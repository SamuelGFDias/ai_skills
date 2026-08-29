---
name: backend-logging
description: Use ao criar, revisar ou corrigir logs em aplicações .NET, garantindo diagnóstico operacional, logging estruturado, contexto suficiente e proteção de dados sensíveis.
---

# Backend Logging (.NET)

## Quando usar

Use quando:

- adicionar logs em fluxo novo;
- investigar falha operacional;
- corrigir excesso ou ausência de logs;
- padronizar níveis de log;
- usar `ILogger<T>`;
- melhorar rastreabilidade de requisições e integrações.

## Objetivo

Produzir logs estruturados e úteis para monitorar atividade, desempenho e falhas da aplicação sem expor dados sensíveis.

## Procedimento

1. Identifique eventos realmente úteis para operação.
2. Use `ILogger<T>` ou abstração equivalente já adotada pelo projeto.
3. Escolha nível adequado:
   - `Critical`: falha crítica com impacto amplo;
   - `Error`: falha que impede conclusão da operação;
   - `Warning`: condição anormal recuperável;
   - `Information`: marco operacional relevante;
   - `Debug`/`Trace`: diagnóstico detalhado.
4. Prefira logging estruturado com templates, por exemplo `logger.LogInformation("Pedido {PedidoId} processado", pedidoId)`.
5. Inclua contexto técnico suficiente: operação, identificador seguro, resultado e correlação.
6. Preserve `TraceIdentifier`, `Activity.TraceId` ou padrão de correlação já adotado.
7. Ao registrar exceção, passe a instância de `Exception` para o logger quando apropriado.
8. Não duplique a mesma exceção em várias camadas sem ganho de informação.
9. Nunca registre senha, token, cookie, connection string, segredo ou payload sensível completo.

## Regras

- mensagem deve explicar o que aconteceu, não apenas `erro ocorreu`;
- prefira placeholders estruturados a interpolação de string em logs frequentes;
- evite serializar objetos inteiros sem necessidade;
- não use `Information` para cada linha de execução;
- log não substitui tratamento correto de erro;
- preserve integração existente com OpenTelemetry, Application Insights, Serilog ou outra stack quando presente.

## Checklist

- [ ] O nível de log está correto?
- [ ] Logging estruturado foi usado quando aplicável?
- [ ] Há contexto suficiente para diagnóstico?
- [ ] Há correlação/trace quando necessário?
- [ ] Não há segredo ou dado sensível?
- [ ] Não existe duplicação de stack trace sem necessidade?
- [ ] Volume em produção continua aceitável?
