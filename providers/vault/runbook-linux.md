# Runbook: HashiCorp Vault (`vault`) como cofre do usuário no Linux (Fedora)

Instalação e configuração do **cliente** `vault` na máquina do usuário. O `arquivos.md` deste diretório trata do uso pelas skills (login, KV v2, escrita segura); este runbook trata de como deixar o ambiente pronto. Nada aqui configura o servidor. Endereços seguem o padrão `<...>` para não expor valores reais.

## 1. Pré-requisitos

- Fedora com `dnf`, acesso `sudo` e `jq` (para filtrar a saída de `token lookup` e `kv get`).
- Conta com acesso ao servidor pelo método de login que a equipe definiu (ex.: LDAP).
- `~/.local/bin` no `PATH`, se usar o `vault-read` (`vault-factory/scripts/init.sh`).

## 2. Instalação do cliente

Repositório dnf oficial da HashiCorp: criar `/etc/yum.repos.d/hashicorp.repo` com `gpgcheck=1`, a URL do canal estável e a da chave conforme a documentação oficial (confirmar as URLs lá antes de criar o arquivo). Depois:

```bash
sudo dnf install vault
vault --version
type -a vault        # esperado: um único caminho; mantenha uma instalação só
```

O pacote instala também `vault.service`: esta máquina é cliente, então deixe-o `disabled` e `inactive`.

## 3. Configuração

Variáveis em `~/.config/ai/refs.env` (modo 600), junto das demais referências:

```bash
VAULT_ADDR="<endereço-do-vault>"
VAULT_CACERT="<caminho-da-ca>"   # só se o CLI reclamar do certificado
```

- **Não** usar `VAULT_SKIP_VERIFY`: desliga a verificação TLS de todo comando do shell. Apontar `VAULT_CACERT` para a CA do servidor.
- Em shell não interativo (agente em bash), carregar antes do uso: `set -a; . ~/.config/ai/refs.env; set +a`.
- O token fica só em `~/.vault-token` (modo `600`, gravado por `vault login`). Nunca exportar `VAULT_TOKEN` nem `VAULT_LDAP_PASSWORD`.
- Login: a senha vai por stdin (`password=-`) e o token não é impresso (`-no-print`), por exemplo
  `printf '%s' "$(vault-read "$SENHA_REF")" | vault login -no-print -method=ldap username=<usuario> password=-`.
  O login é do usuário, não do agente.

## 4. Verificação (nenhum comando imprime segredo)

```bash
stat -c '%a %n' ~/.vault-token                                            # esperado: 600
env | grep '^VAULT_' | cut -d= -f1                                        # só nomes; nunca VAULT_TOKEN nem VAULT_SKIP_VERIFY
vault token lookup -format=json | jq '.data|{display_name,policies,expire_time}'
vault kv list -mount=<mount> <prefixo>/                                   # só nomes de caminhos
```

## 5. Troubleshooting

| Sintoma | Causa | Ação |
|---|---|---|
| 403 / `permission denied` | Token expirado ou sem policy para o caminho | `vault token lookup` com filtro; refazer o login; conferir o grupo com a equipe |
| 403 com "preflight capability check" | Caminho usado como mount | Usar `-mount=<mount>` seguido do caminho |
| `x509: certificate signed by unknown authority` | CA do servidor não confiada | Definir `VAULT_CACERT`; não usar `VAULT_SKIP_VERIFY` |
| `connection refused` em `127.0.0.1:8200` | `VAULT_ADDR` ausente | Definir `VAULT_ADDR` em `refs.env` |
| Chaves sumiram de um secret | `kv put` em secret existente | Ver "Escrita segura" em `arquivos.md`; restaurar com `vault kv rollback` |

## 6. Regras de segurança

- **Nunca** imprimir o token nem a senha no chat, em log ou no histórico do shell.
- `vault token lookup` só com filtro `jq`, nunca com a saída crua.
- Agentes listam só nomes de chaves; a leitura de valor fica em script que o usuário roda (ver `arquivos.md`).
- Nunca commitar `~/.vault-token` nem `refs.env` com valores reais.
- Se o token for exposto: `vault token revoke -self` e novo login.
