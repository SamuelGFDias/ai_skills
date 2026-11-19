---
name: kde-plasma-widgets
description: Cria e mantém widgets (plasmoids) e itens de painel do KDE Plasma 6 em QML, com modelo pronto (ícone no painel que abre um menu, lista de cartões, configurações, ponte para script externo) e scripts para gerar, validar, recarregar e posicionar o widget. Use quando o usuário pedir um widget, applet, plasmoid, item de painel, ícone de bandeja ou menu no painel do KDE/Plasma, ou para corrigir, redesenhar ou depurar um widget QML existente.
---

# Skill: kde-plasma-widgets

**Tipo:** open-source — procedimento genérico para Plasma 6 (Qt 6). Não cobre Plasma 5.

## Quando executar

- O usuário quer um widget novo no KDE: na área de trabalho ou como ícone no painel que abre um menu.
- O usuário quer controlar ou acompanhar algo (dispositivos, serviços, uma API, um comando) a partir do painel.
- Um widget QML existente precisa de correção, novo visual ou nova função.
- Um widget some, duplica, não atualiza ou dá erro no `plasmashell`.

Antes de começar, confirme a versão: `plasmashell --version` tem de ser 6.x.

## Como um widget é montado

Um widget é uma pasta com `metadata.json` e QML em `contents/ui/`. O mesmo widget serve nos
dois lugares: no painel ele mostra a `compactRepresentation` (o ícone) e, ao clicar, a
`fullRepresentation` (o menu). Na área de trabalho mostra direto a `fullRepresentation`.

QML não acessa rede local nem bibliotecas. A lógica fica num script em `contents/code/` que
imprime uma linha JSON por chamada; o QML o executa e desenha o resultado.

## Fluxo

| Passo | O que fazer | Como |
|---|---|---|
| 1 | Gerar o widget a partir do modelo | `scripts/new-widget.sh <Id> "<Nome>" <pasta> --link` |
| 2 | Escrever a ponte e testá-la sozinha no terminal | `contents/code/bridge.py`, com testes unitários das funções puras |
| 3 | Adaptar `main.qml` e os cartões ao que a ponte devolve | ver `docs/referencia.md` |
| 4 | Validar e recarregar a cada mudança | `scripts/reload.sh <Id>` |
| 5 | Conferir o visual | `scripts/preview.sh <Id> saida.png`, e abrir a imagem |
| 6 | Pôr no painel | `scripts/panel.sh add <Id>` ou "Adicionar widgets" |
| 7 | Versionar | pergunte ao usuário onde; segredos e estado ficam fora do repo |

O `Id` (ex.: `org.<dono>.<nome>`) vira o nome da pasta instalada em
`~/.local/share/plasma/plasmoids/`. Com `--link` o script cria um symlink para a pasta de
desenvolvimento, que dispensa reinstalar a cada mudança.

## O que o modelo já traz

`templates/widget/` é um widget que funciona como está: ícone no painel, menu com lista de
cartões, página de configurações e uma ponte de exemplo.

- `main.qml`: chamada da ponte com `nonce` e argumentos escapados, atualização periódica,
  resposta otimista, modelo atualizado no lugar e animação de entrada e saída das linhas.
- `ItemRow.qml`: cartão com botão liga/desliga, nome, estado e barra de nível.
- `PillSlider.qml`: barra em forma de pílula que não reage à roda do mouse e não "volta" ao
  valor antigo enquanto o comando está em andamento. Aceita degradê (`trackGradient`).
- `Chip.qml`: botão em pílula para ações rápidas e opções.
- `bridge.py`: comandos `status`, `toggle` e `level`, sempre com uma linha JSON de saída.

Troque a ponte pela fonte real e ajuste os campos. Mantenha os padrões do `main.qml`: cada um
existe por causa de um defeito descrito em `docs/armadilhas.md`.

## Regras que evitam retrabalho

1. **Leia `docs/armadilhas.md` antes de escrever QML.** São erros silenciosos: nada aparece no
   log e a tela só fica errada.
2. **O `plasmashell` guarda o QML em memória.** Editar o arquivo não muda o widget carregado;
   rode `scripts/reload.sh`. Mudança em `config/main.xml` também exige reinício.
3. **Nunca diga que o visual está certo sem ver.** O lint e o log limpo provam que carrega,
   não que está bonito nem que o clique funciona. Capture a tela, ou peça ao usuário para
   testar e diga o que não foi verificado.
4. **Reiniciar o `plasmashell` pisca o painel do usuário.** Agrupe mudanças antes de recarregar
   e avise quando for fazer.
5. **Depois de adicionar ou remover um widget por script, espere uns 10 s antes de reiniciar.**
   Reiniciar logo em seguida duplica o widget. O `reload.sh` conta as instâncias e avisa.
6. **Ações que mexem em coisas reais** (ligar aparelho, enviar comando) durante um teste:
   avise antes e devolva ao estado em que estava.
7. **Segredos** (chaves, tokens) nunca entram no widget nem no repo. A ponte lê de um arquivo
   em `~/.config/<nome>/` com modo 600 ou do cofre do usuário (ver skill `vault-factory`).
8. **Dependência Python** vai num venv fora do repo. O caminho do interpretador é uma chave de
   configuração do widget, porque o `plasmashell` não herda o ambiente do terminal.

## Scripts

| Script | Uso |
|---|---|
| `scripts/new-widget.sh <Id> "<Nome>" [pasta] [--link]` | Copia o modelo e preenche Id, nome e autor. |
| `scripts/reload.sh <Id> [pasta] [--no-restart]` | `qmllint` filtrado, reinício do `plasmashell`, erros do log e contagem de instâncias. |
| `scripts/preview.sh <Id> <saida.png> [segundos]` | Abre o menu numa janela e captura a janela ativa. |
| `scripts/panel.sh list\|add\|remove\|get\|set` | Lista, adiciona, remove e configura widgets pelo D-Bus. |

Limites conhecidos: o `preview.sh` captura a janela ativa, então sai a janela errada se o
usuário estiver usando outra; e não há como clicar no widget por script, portanto estados que
dependem de clique (cartão aberto, modo de edição) só o usuário consegue conferir. A posição
do widget dentro do painel também não é ajustável por script: é arrastando no modo de edição.

## Referências

- `docs/referencia.md`: `metadata.json`, representações, configurações, ponte, notificações,
  comandos de instalação e o `evaluateScript`.
- `docs/armadilhas.md`: os erros de QML e de ambiente já encontrados, com causa e correção.

## Verificação antes de entregar

- [ ] `scripts/reload.sh <Id>` sem erros de lint e sem linhas do widget no log.
- [ ] Uma única instância no layout.
- [ ] A ponte responde no terminal com JSON válido, inclusive em erro.
- [ ] Captura de tela conferida, ou dito claramente o que não foi visto.
- [ ] Nenhum segredo nem caminho de máquina nos arquivos versionados.
