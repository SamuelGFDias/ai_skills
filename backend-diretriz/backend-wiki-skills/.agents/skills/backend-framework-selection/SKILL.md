---
name: backend-framework-selection
description: Use ao iniciar ou modernizar um backend Java e precisar escolher entre Spring Boot e Quarkus conforme requisitos de aplicação, operação e ambiente cloud-native.
---

# Backend Framework Selection

## Quando usar

Use apenas quando houver uma decisão real de framework, por exemplo:

- criação de um novo serviço Java;
- migração relevante de runtime/framework;
- avaliação de Spring Boot versus Quarkus;
- necessidade de otimização para Kubernetes/GraalVM/compilação nativa.

Não use para uma alteração comum dentro de um projeto cujo framework já está definido.

## Diretriz

A fonte arquitetural acessível contempla dois frameworks principais:

- **Spring Boot**: ecossistema maduro, ampla integração e grande disponibilidade de bibliotecas;
- **Quarkus**: abordagem cloud-native, otimizada para Kubernetes e GraalVM, com suporte a compilação nativa.

## Processo de decisão

1. Verifique o framework padrão já adotado pela organização/projeto.
2. Levante requisitos operacionais:
   - tempo de startup;
   - consumo de memória;
   - execução em contêiner;
   - Kubernetes/OpenShift;
   - necessidade de native image;
   - bibliotecas e integrações exigidas.
3. Verifique maturidade e conhecimento da equipe.
4. Verifique compatibilidade com autenticação, observabilidade, persistência e pipeline existentes.
5. Escolha o framework com menor risco operacional e melhor aderência ao ecossistema já mantido.
6. Registre a decisão e os trade-offs.

## Não fazer

- não trocar framework apenas por preferência pessoal;
- não introduzir Quarkus apenas por ser cloud-native se o ganho não justificar migração;
- não escolher Spring Boot ignorando requisitos reais de footprint/startup quando eles forem críticos;
- não criar uma arquitetura híbrida sem razão documentada.

## Checklist

- [ ] O framework atual foi identificado?
- [ ] Requisitos de runtime foram levantados?
- [ ] Dependências e integrações foram verificadas?
- [ ] Operação em contêiner/Kubernetes foi considerada?
- [ ] A decisão reduz risco e custo de manutenção?
- [ ] Trade-offs foram documentados?
