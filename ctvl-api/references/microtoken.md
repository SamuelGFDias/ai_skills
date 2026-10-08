# Microtoken: como a aplicação consome a tokenização

Origem: skill `microtoken-integration` escrita pelo time de desenvolvimento do vault (copiada de `~/Downloads/SKILL.md`, adaptada para o padrão deste repo). Ela vale para o **projeto consumidor** (a aplicação), não para quem administra o CT-VL.

Microtoken é uma API HTTP na frente do CT-VL. **A aplicação nunca fala com o CT-VL diretamente**: nem com a API de dados (`/vts/rest/v2.0/*`, Basic) nem com a admin. A skill `ctvl-api` administra o vault por trás; o microtoken é o que o app enxerga.

## Antes de escrever código, perguntar ao usuário

Não adivinhar; parar até ter as respostas:

1. **Datatypes** que o projeto usa (ex.: `cpf`, `email`). Configurados pelo admin do microtoken; não existe endpoint para listá-los.
2. **Modo de detokenização** da API key do projeto: **clear**, só **masked**, ou nenhuma.
3. **Onde o cliente mora** e como a config é lida no projeto (env, settings, secret manager).

Depois detectar linguagem, cliente HTTP e framework de teste do projeto e seguir as convenções dele. Não adicionar biblioteca HTTP nova se já houver uma.

## Configuração

- `MICROTOKEN_URL`: URL base, sem barra final.
- `MICROTOKEN_API_KEY`: chave (`mtk_…`), emitida uma vez pelo admin.

Ler do ambiente ou do secret store do projeto. Nunca hardcode, commit, log, nem enviar a chave a código de browser/mobile: chamar o microtoken só do servidor. Incluir os dois nomes no `.env.example` (ou equivalente) com valor vazio. Entrega da chave ao projeto: skill `vault-factory`, nunca chat/e-mail.

## API

Toda chamada: `POST`, headers `Content-Type: application/json` e `X-API-Key: <chave>`. O datatype vai no path **e** é o nome do campo JSON.

**Tokenizar**: `POST /tokenize/{datatype}`

```
request:  {"cpf": "111.111.111-11"}
response: {"token": "t0#8tDWwe-OjS", "status": "Succeed"}
```

**Detokenizar**: `POST /detokenize/{datatype}?clear=false` (`clear=true` devolve o texto claro, só se o perfil da chave permitir)

```
request:  {"cpf": "t0#8tDWwe-OjS"}
response: {"data": "111***********", "status": "Succeed"}
```

**Lote**: enviar uma lista de objetos JSON a qualquer dos endpoints; a resposta é uma lista na mesma ordem. Preferir lote para muitos valores. Esquema completo em `<MICROTOKEN_URL>/docs`.

## Erros

JSON `{"error": "...", "request_id": "..."}`, mais `upstream_status` só quando o CT-VL respondeu. O request id também vem no header `X-Request-ID`. Levantar erro tipado com status, `error` e `request_id`; logar o `request_id` (nunca o valor tokenizado).

| Status | Significado | O que fazer |
|---|---|---|
| 400 | JSON inválido, campo do datatype ausente no corpo, ou datatype não configurado | Bug ou config: não repetir |
| 401 | API key inválida, revogada ou ausente | Config: não repetir |
| 403 | O perfil da chave não pode essa operação nesse datatype (ex.: detokenize em claro) | Não repetir; pedir ao admin |
| 500 | Erro inesperado no microtoken | Não repetir às cegas; reportar o `request_id` |
| 502 | CT-VL inacessível, resposta inválida ou rejeitou a requisição | Repetir com backoff (poucas tentativas) |
| 503 | O datatype não tem credencial no CT-VL para essa operação | Config: não repetir |
| 504 | Timeout do CT-VL | Repetir com backoff (poucas tentativas) |

## O que construir no projeto

1. Módulo cliente com `tokenize(datatype, valor)`, `detokenize(datatype, token, clear=false)` e variantes em lote, com **um** cliente HTTP compartilhado e timeout (~10 s).
2. O erro tipado e a política de retry acima (só 502/504).
3. Testes com HTTP mockado (nunca o microtoken real): sucesso, ordem do lote, parâmetro `clear`, cada status de erro, retry só em 502/504 e envio do header da API key.
4. Uso nos pontos de chamada que o usuário indicar. Guardar e comparar tokens como strings opacas; nunca parsear nem validar o formato.

## Implementação de referência (Python)

```python
# pip install requests
import os

import requests

MICROTOKEN_URL = os.environ["MICROTOKEN_URL"]  # ex.: https://microtoken.example.com
MICROTOKEN_API_KEY = os.environ["MICROTOKEN_API_KEY"]


class MicrotokenError(Exception):
    def __init__(self, status, error, request_id):
        super().__init__(f"{status} {error} (request_id={request_id})")
        self.status, self.error, self.request_id = status, error, request_id


def _call(path, body, params=None):
    res = requests.post(
        MICROTOKEN_URL.rstrip("/") + path,
        json=body,
        params=params,
        headers={"X-API-Key": MICROTOKEN_API_KEY},
        timeout=10,
    )
    if not res.ok:
        try:
            err = res.json()
        except ValueError:
            err = {}
        raise MicrotokenError(res.status_code, err.get("error", res.text), err.get("request_id"))
    return res.json()


def tokenize(datatype, value):
    return _call(f"/tokenize/{datatype}", {datatype: value})["token"]


def detokenize(datatype, token, clear=False):
    return _call(f"/detokenize/{datatype}", {datatype: token}, {"clear": str(clear).lower()})["data"]
```

Sem retry no exemplo: o cliente real do projeto deve aplicar a política de 502/504.

## Pontos a confirmar com a equipe do vault (a skill não adivinha)

- **Como o perfil da API key (clear / masked / nenhum) se liga ao vault**: presumivelmente a um usuário de dados do CT-VL (com ou sem `mask`, `canGet` true/false), mas o documento do time não diz. Confirmar antes de usar `enable-detokenize` para "liberar clear" a um app.
- **Normalização do valor**: o exemplo do time tokeniza `111.111.111-11` (formatado) e a detokenização mascarada devolve `111***********` (14 posições). Nas medições diretas em DEV da API de dados, entrada formatada gera token diferente e maior, e a recomendação é normalizar para só dígitos. Confirmar se o microtoken normaliza ou repassa o valor como veio.
- **Limite de lote** do microtoken (a API de dados direta aceita 5000; 5156 falha).
- **Mapeamento datatype do microtoken ↔ `<sistema>_<datatype>`** (tokengroup/template) do `ctvl-api`.
