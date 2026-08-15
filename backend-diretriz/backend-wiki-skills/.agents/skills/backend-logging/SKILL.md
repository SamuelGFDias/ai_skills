---
name: backend-logging
description: Use ao criar, revisar ou corrigir logs de backend, garantindo diagnóstico operacional, contexto suficiente e proteção de dados sensíveis.
---

# Backend Logging

## Quando usar

Use quando:

- adicionar logs em fluxo novo;
- investigar falha operacional;
- corrigir excesso ou ausência de logs;
- padronizar níveis de log;
- melhorar rastreabilidade de requisições e integrações.

## Objetivo

Produzir logs úteis para monitorar atividade e desempenho da aplicação e diagnosticar falhas sem expor dados sensíveis.

## Procedimento

1. Identifique eventos realmente úteis para operação.
2. Escolha nível adequado:
   - `ERROR`: falha que impede conclusão ou exige atenção;
   - `WARN`: condição anormal recuperável;
   - `INFO`: marco operacional relevante;
   - `DEBUG/TRACE`: diagnóstico detalhado, não essencial em produção.
3. Inclua contexto técnico suficiente: operação, identificador seguro, resultado.
4. Use correlação/request-id quando o projeto possuir esse padrão.
5. Não duplique a mesma exceção em várias camadas sem ganho de informação.
6. Nunca registre segredo, senha, token, cookie de sessão ou payload sensível completo.

## Regras

- mensagem deve explicar o que aconteceu, não apenas `erro ocorreu`;
- evite concatenar objetos gigantes em log;
- prefira logging estruturado quando a stack já suportar;
- não use `INFO` para cada linha de execução;
- log não substitui tratamento correto de erro.

## Checklist

- [ ] O nível de log está correto?
- [ ] Há contexto suficiente para diagnóstico?
- [ ] Não há segredo/dado sensível?
- [ ] Não existe duplicação de stack trace sem necessidade?
- [ ] Volume em produção continua aceitável?
