---
name: backend-framework-selection
description: Use ao iniciar ou modernizar um backend .NET e precisar escolher o modelo de aplicação ASP.NET Core mais adequado, considerando Controllers, Minimal APIs, Worker Services, runtime e requisitos operacionais.
---

# Backend Framework Selection (.NET)

## Quando usar

Use apenas quando houver uma decisão real de modelo/framework de aplicação, por exemplo:

- criação de um novo serviço .NET;
- escolha entre ASP.NET Core Controllers e Minimal APIs;
- criação de API HTTP versus Worker Service/background processing;
- modernização relevante de aplicação .NET legada;
- decisão de versão LTS/STS do .NET;
- requisitos especiais de containers, Kubernetes/OpenShift, Native AOT ou footprint.

Não use para uma alteração comum dentro de projeto cujo modelo já está definido.

## Diretriz

Em backend .NET, preserve ASP.NET Core como padrão para serviços HTTP e escolha o modelo de programação com base no contexto:

- **Controllers**: apropriados quando o projeto possui APIs maiores, filtros, convenções MVC, versionamento, atributos e organização por controllers;
- **Minimal APIs**: apropriadas para APIs menores, endpoints simples ou projetos que já adotem esse estilo;
- **Worker Service / `BackgroundService`**: apropriado para processamento assíncrono sem API HTTP como responsabilidade principal.

Native AOT deve ser tratado como requisito arquitetural, pois restringe reflexão e compatibilidade de bibliotecas.

## Processo de decisão

1. Verifique o padrão já adotado pela organização e pelo repositório.
2. Identifique a versão do .NET suportada pelo ambiente de execução.
3. Levante requisitos operacionais:
   - tempo de startup;
   - consumo de memória;
   - execução em contêiner;
   - Kubernetes/OpenShift;
   - necessidade de Native AOT;
   - observabilidade;
   - autenticação;
   - persistência;
   - bibliotecas e integrações exigidas.
4. Verifique maturidade e conhecimento da equipe.
5. Verifique compatibilidade com pipeline, imagens base e infraestrutura existente.
6. Preserve Controllers/Minimal APIs existentes quando não houver ganho comprovado na troca.
7. Escolha a opção com menor risco operacional e melhor aderência ao ecossistema mantido.
8. Registre a decisão e os trade-offs quando ela for arquiteturalmente relevante.

## Não fazer

- não trocar Controllers por Minimal APIs apenas por preferência pessoal;
- não introduzir Native AOT sem validar todas as dependências;
- não selecionar versão do .NET ignorando suporte do ambiente e pipeline;
- não criar arquitetura híbrida sem razão documentada;
- não migrar aplicação legada e redesenhar toda a arquitetura na mesma mudança sem necessidade.

## Checklist

- [ ] O padrão atual do projeto foi identificado?
- [ ] A versão do .NET suportada foi verificada?
- [ ] Requisitos de runtime foram levantados?
- [ ] Dependências e integrações foram verificadas?
- [ ] Operação em contêiner/Kubernetes foi considerada?
- [ ] Native AOT foi tratado apenas quando necessário?
- [ ] A decisão reduz risco e custo de manutenção?
- [ ] Trade-offs foram documentados quando necessário?
