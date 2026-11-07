# Segredo exposto em arquivo versionado

Use quando o validador (ou uma revisão) apontar um segredo em texto claro num arquivo do repositório.
O alerta mostra **uma** ocorrência; o valor pode estar em outras linhas, em outros arquivos e no
histórico. Corrigir só a linha apontada não prova que o valor saiu.

## Regras

- Nunca imprima o valor: nem no terminal, nem no chat, nem em log. Extraia para um arquivo temporário
  com permissão `0600` e use `-f` nas buscas.
- Só declare "removido" com **zero ocorrências no working tree** e relatando à parte o que continua
  no histórico.
- Reescrever o histórico **não invalida o segredo**: quem o copiou antes continua com ele. A ação que
  neutraliza o vazamento é trocar a credencial na origem. Reescreva o histórico só depois disso, e só
  com confirmação do usuário (exige force-push e todos os clones precisam ser refeitos).
- Confirme com o usuário se o valor é uma credencial real ou só um exemplo, antes de qualquer ação
  destrutiva.

## Passo a passo

```bash
# 1. extrair o valor sem imprimir: pega o conteúdo entre as primeiras aspas da linha apontada
#    (vale para `chave = 'valor'` e `--opcao 'valor'`; valor sem aspas exige outro sed)
umask 077; SEG=$(mktemp)
git show HEAD:<caminho> | sed -n '<N>p' | sed -nE "s/^[^'\"]*['\"]([^'\"]*)['\"].*/\1/p" > "$SEG"
[ -s "$SEG" ] || echo "extração vazia: ajuste o padrão antes de seguir" >&2   # vazio varre tudo

# 2. onde o valor aparece hoje (só caminhos e números de linha, sem o conteúdo)
git grep -n -F -f "$SEG" HEAD -- . | cut -d: -f2,3

# 3. onde aparece no histórico (quantos commits e quais arquivos)
git rev-list --all | while read c; do git grep -l -F -f "$SEG" "$c" -- . 2>/dev/null; done \
  | sed 's/^[0-9a-f]*://' | sort | uniq -c

# 4. trocar TODAS as ocorrências do working tree por um placeholder e repetir o passo 2
#    (deve voltar vazio); depois apagar o temporário
rm -f "$SEG"
```

## Depois

1. Peça ao usuário para **trocar a credencial** na origem (Passbolt, AD, Vault etc.).
2. Se o usuário quiser limpar o histórico: faça num clone temporário (`git filter-branch` ou
   `git filter-repo`), confira que nenhum commit alcançável contém o valor, mostre o resultado e só
   então faça o force-push com a confirmação dele. Avise que as refs de MRs antigas no servidor ainda
   guardam os commits antigos até o administrador do GitLab limpá-las.
3. Apague o clone temporário e qualquer arquivo com o valor.
