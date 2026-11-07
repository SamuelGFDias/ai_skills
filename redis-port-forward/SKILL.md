---
name: redis-port-forward
description: Abre um túnel local (oc port-forward) até o Redis (svc/redis-master) dos clusters OpenShift SES-RJ nos ambientes DEV, HML e PRD, para acessar com redis-cli sem expor o serviço publicamente. Use quando o usuário pedir para conectar/depurar/consultar o Redis de algum ambiente SES-RJ.
---

# Skill: redis-port-forward

**Tipo:** internal

## Quando executar

Pedidos para acessar, depurar ou consultar chaves do Redis dos ambientes SES-RJ (DEV/HML/PRD) a
partir da máquina local.

## Pré-requisitos

- Skill `openshift-cli` — `oc` instalado e autenticado no cluster do ambiente desejado
  (`oc login`, ver `SKILL.md` daquela skill).
- `redis-cli` instalado (`sudo dnf install -y redis` no Fedora; `apt install redis-tools` no
  Debian/Ubuntu).
- Senha do Redis guardada no cofre (`pass show redis/<env>/senha` — obter via Passbolt/gopass,
  runbook `Runbook — Gopass e Pass` na wiki). Nunca ecoar essa senha isolada no terminal.
- Confirmar acesso ao namespace antes de tentar (`oc get projects` pode não listar o namespace do
  Redis mesmo tendo acesso, se a listagem estiver truncada — tentar o port-forward direto se tiver
  certeza do nome do namespace).

Fonte oficial: `wiki.saude.rj.gov.br/en/desenvolvimento/redis/runbook/portfowarding`.

## Namespaces por ambiente

| Ambiente | Namespace |
|---|---|
| DEV | `redis-dev` |
| HML | `redis-hml` |
| PRD | `redis-prd` |

## Abrir o túnel

Num terminal (fica bloqueando enquanto o túnel estiver ativo):

```bash
oc port-forward svc/redis-master 6379:6379 -n redis-<env>   # <env> = dev | hml | prd
```

Se a porta local 6379 já estiver em uso, mapear para outra: `6380:6379` (e conectar em `6380`).

## Testar em outro terminal

```bash
redis-cli -h 127.0.0.1 -p 6379 -a "$(pass show redis/<env>/senha)" ping   # deve responder PONG
redis-cli -h 127.0.0.1 -p 6379 -a "$(pass show redis/<env>/senha)" get <CHAVE>
redis-cli -h 127.0.0.1 -p 6379 -a "$(pass show redis/<env>/senha)" info
```

Sempre usar `$(pass show ...)` inline — nunca colar a senha em texto puro no comando/histórico.

## Encerrar

`Ctrl+C` no terminal onde o `oc port-forward` está rodando.

## Troubleshooting

| Problema | Solução |
|---|---|
| `error: You must be logged in to the server` | `oc login` no cluster do ambiente (skill `openshift-cli`) |
| `error: the server is currently unable to handle the request` | Checar rede/VPN e se o cluster está acessível |
| Porta local já em uso | Mapear outra porta local, ex. `6380:6379` |
| `redis-cli: command not found` | Instalar o cliente Redis (ver Pré-requisitos) |
| `NOAUTH Authentication required` | Passar `-a "<SENHA>"` ou autenticar com `AUTH` no `redis-cli` |
| `DENIED Redis is running in protected mode` | Conectar via `127.0.0.1` — já é o padrão do port-forward |
