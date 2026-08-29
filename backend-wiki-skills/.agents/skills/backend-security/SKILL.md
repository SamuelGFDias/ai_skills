---
name: backend-security
description: Use ao implementar ou revisar autenticação e autorização em ASP.NET Core, incluindo JWT, OAuth2, OpenID Connect, policies, roles, claims e controle de acesso a endpoints.
---

# Backend Security (.NET)

## Quando usar

Use quando houver:

- autenticação;
- autorização;
- ASP.NET Core Authentication/Authorization;
- JWT Bearer;
- OAuth2/OIDC;
- Keycloak, Microsoft Entra ID ou outro Identity Provider;
- roles, claims, policies ou scopes;
- endpoints públicos versus protegidos;
- mudança em regras de acesso.

## Objetivo

Garantir que somente clientes e usuários autenticados e autorizados tenham acesso aos recursos correspondentes, usando os mecanismos nativos do ASP.NET Core e o princípio do menor privilégio.

## Procedimento

1. Identifique o mecanismo de identidade existente e preserve o provider/configuração atual.
2. Revise `AddAuthentication`, `AddAuthorization` e os handlers/schemes configurados.
3. Descubra quais endpoints são públicos e quais exigem autenticação.
4. Modele autorização pelo menor privilégio necessário usando policies, roles, claims ou handlers conforme o padrão do projeto.
5. Prefira `[Authorize]`, policies, endpoint metadata e `IAuthorizationService` aos checks manuais dispersos.
6. Não valide JWT manualmente se `JwtBearer` ou handler apropriado já atende ao cenário.
7. Valide autenticação e autorização separadamente.
8. Garanta respostas seguras e coerentes para `401 Unauthorized` e `403 Forbidden`.
9. Não registre token, senha, segredo, cookie ou credencial em logs.
10. Adicione testes para acesso permitido e negado.

## Regras

- negar por padrão quando a regra de acesso for ambígua;
- autorização deve ocorrer no backend mesmo que o frontend esconda funcionalidades;
- token válido não significa autorização para qualquer recurso;
- valide `issuer`, `audience`, assinatura e expiração conforme configuração de segurança adotada;
- dados sensíveis podem exigir autorização por recurso, usuário, unidade ou tenant;
- nunca confiar em role/claim enviada livremente pelo cliente como dado de negócio;
- não desabilite validações criptográficas ou HTTPS apenas para fazer integração funcionar;
- preserve secrets fora do código-fonte.

## Checklist

- [ ] O scheme de autenticação correto está configurado?
- [ ] Endpoint exige autenticação quando necessário?
- [ ] A autorização aplica menor privilégio?
- [ ] Policies/roles/claims estão coerentes?
- [ ] Cenários `401` e `403` foram testados?
- [ ] Segredos e tokens não aparecem em logs/respostas?
- [ ] Regras nativas do ASP.NET Core são usadas de forma consistente?
- [ ] Não há confiança indevida no frontend?
