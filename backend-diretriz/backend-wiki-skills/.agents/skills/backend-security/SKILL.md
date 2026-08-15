---
name: backend-security
description: Use ao implementar ou revisar autenticação, autorização, Spring Security, JWT/OAuth2 e regras de acesso a endpoints e recursos.
---

# Backend Security

## Quando usar

Use quando houver:

- autenticação;
- autorização;
- Spring Security;
- JWT/OAuth2/OIDC;
- roles/perfis/escopos;
- endpoints públicos versus protegidos;
- mudança em regras de acesso.

## Objetivo

Garantir que somente clientes e usuários autorizados tenham acesso aos recursos correspondentes, com controles explícitos e verificáveis.

## Procedimento

1. Identifique o mecanismo de identidade existente.
2. Descubra quais endpoints são públicos e quais exigem autenticação.
3. Modele autorização pelo menor privilégio necessário.
4. Evite duplicar validação de token manualmente quando o framework já fornece suporte adequado.
5. Valide autenticação e autorização separadamente.
6. Garanta que falhas retornem respostas seguras e coerentes.
7. Não registre token, senha, segredo ou credencial em logs.
8. Adicione testes para acesso permitido e negado.

## Regras

- negar por padrão quando a regra de acesso for ambígua;
- autorização deve ocorrer no backend mesmo que o frontend esconda funcionalidades;
- token válido não significa autorização para qualquer recurso;
- dados sensíveis precisam de validação adicional quando houver escopo por usuário/unidade/tenant;
- nunca confiar em role enviada livremente pelo cliente como dado de negócio.

## Checklist

- [ ] Endpoint exige a autenticação correta?
- [ ] A autorização aplica menor privilégio?
- [ ] Cenário negado foi testado?
- [ ] Segredos e tokens não aparecem em logs/respostas?
- [ ] Regras do framework são usadas de forma consistente?
- [ ] Não há confiança indevida no frontend?
