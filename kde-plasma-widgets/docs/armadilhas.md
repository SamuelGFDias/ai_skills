# Armadilhas já encontradas

Erros que não aparecem no log: a tela só fica errada. Leia antes de escrever QML.
O modelo em `templates/widget/` já evita todos.

## QML

1. **`id` com o mesmo nome de uma propriedade.** Um `Slider { id: temp }` dentro de um
   componente com `property int temp` faz `temp` passar a ser o slider. A conta com o valor
   dá `NaN` sem erro nenhum. Dê nomes diferentes (`tempSlider`).
2. **Papel do modelo com nome de propriedade do item.** Um delegate `Rectangle` com
   `required property string color` colide com `Rectangle.color`. O `qmllint` avisa
   ("already exists in base type"). Renomeie (`lampColor`).
3. **Roda do mouse em sliders dentro de lista.** O slider captura a rolagem e muda o valor
   em vez de rolar a lista. Ponha `wheelEnabled: false`; em slider próprio, recuse o evento
   (`onWheel: wheel.accepted = false`).
4. **Slider que "vai e volta".** Se o valor do slider é ligado ao estado real e o comando
   demora, ao soltar o mouse ele volta ao valor antigo e depois anima até o novo. Solução:
   o slider guarda o valor escolhido e ignora o valor externo enquanto está pressionado e
   por alguns segundos depois (ver `templates/widget/contents/ui/PillSlider.qml`).
5. **Transições da `ListView` junto com animação de altura.** `move`/`displaced` animam o `y`
   das linhas com base na altura antiga; se um cartão cresce ao mesmo tempo, as linhas ficam
   uma por cima da outra. O que funcionou: nenhuma transição na lista, e cada linha anima a
   própria altura (propriedade `reveal` de 0 a 1 em `ListView.onAdd` e, com
   `ListView.delayRemove`, de 1 a 0 em `ListView.onRemove`). Para reordenar, remova a linha
   e insira no lugar novo.
6. **`spacing` da `ListView` não encolhe.** Uma linha com altura zero ainda ocupa o
   espaçamento. Ponha o espaço dentro da linha (`height: (cartao.implicitHeight + gap) * reveal`)
   e deixe `spacing: 0`.
7. **Atualizar o modelo sem recriar.** Trocar o `ListModel` inteiro a cada consulta destrói
   os delegates: perde o arraste em andamento e o estado de "aberto". Atualize no lugar com
   `set`, `insert` e `remove`, e guarde estado de interface (o que está expandido) fora do
   delegate, num objeto da raiz.
8. **Resposta parcial não é lista completa.** Se um comando devolve só o item alterado, não
   use essa resposta para remover os itens "ausentes". Só a consulta completa pode limpar.
9. **Campos de texto somem ao atualizar.** Um `Repeater` sobre um array é recriado quando o
   array muda. Pause a atualização periódica enquanto o usuário edita.
10. **Cabeçalho que não alinha à direita.** Num `RowLayout`, o item que deve empurrar os
    outros precisa de `Layout.fillWidth: true`, e os textos dentro dele também.

## Ambiente

1. **Editar o QML não muda o widget carregado.** O `plasmashell` guarda o QML em memória.
   Só `systemctl --user restart plasma-plasmashell` (ou `scripts/reload.sh`) carrega a versão nova.
2. **Widget duplicado depois de reiniciar.** Acontece quando o `plasmashell` é reiniciado logo
   após um `addWidget` ou `remove` por script, antes de o layout ser gravado. Espere uns 10 s,
   ou confira com `scripts/panel.sh list` e remova o extra.
3. **Ícone do tema que não existe aparece em branco, sem erro.** Confira o nome nos temas
   instalados (`find /usr/share/icons -name "<nome>.svg"`) ou use um SVG próprio em `contents/icons/`.
4. **Ícone invisível no painel.** A `compactRepresentation` precisa de `Layout.minimumWidth` e
   `Layout.minimumHeight`; sem eles fica com largura zero.
5. **O `qmllint` reclama de quase tudo.** "Unqualified access" e "Could not find property
   onAdd/onRemove" são ruído. `Error` e "already exists in base type" são reais.
6. **O `plasmashell` não herda o ambiente do terminal.** `PATH`, venv ativo e variáveis
   exportadas no shell não chegam ao script. Use caminhos absolutos ou uma chave de configuração.
7. **Captura de tela da janela errada.** `spectacle -a` pega a janela ativa. Se o usuário
   estiver trabalhando em outra, a imagem não é do widget. Abra e confira.
8. **Janela de teste recebe cliques.** Um `plasmawindowed` aberto durante um teste é um widget
   de verdade: se o usuário clicar nele, comandos reais são enviados e o estado muda.
9. **Resposta lenta da ponte.** Cada chamada sobe um processo novo. Agrupe o que puder numa
   chamada só (um alvo com várias ids) e consulte dispositivos em paralelo dentro do script.
10. **Falha isolada não é queda.** Dispositivos de rede perdem uma consulta de vez em quando.
    Tente de novo antes de marcar como offline e só notifique depois de duas falhas seguidas.
