# Referência: widgets do Plasma 6

Detalhes de cada parte de um widget. O modelo em `templates/widget/` já aplica tudo isto.

## Estrutura mínima

```
org.exemplo.meuwidget/
  metadata.json
  contents/
    ui/main.qml            obrigatório: a interface
    ui/configGeneral.qml   opcional: página de configurações
    config/main.xml        opcional: chaves de configuração e seus padrões
    config/config.qml      opcional: lista as páginas de configuração
    code/                  opcional: scripts que o widget chama
    icons/                 opcional: ícones próprios (SVG)
```

`metadata.json`:

```json
{
    "KPlugin": {
        "Id": "org.exemplo.meuwidget",
        "Name": "Meu widget",
        "Description": "O que ele faz, em uma linha",
        "Icon": "preferences-desktop-color",
        "Category": "Utilities",
        "Version": "0.1",
        "License": "MIT",
        "Authors": [{"Name": "<seu nome>"}]
    },
    "KPackageStructure": "Plasma/Applet",
    "X-Plasma-API-Minimum-Version": "6.0"
}
```

O nome da pasta instalada tem de ser igual ao `Id`.

## O `main.qml`

```qml
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    toolTipMainText: "Meu widget"
    toolTipSubText: "Texto que aparece ao passar o mouse"

    // Ícone no painel
    compactRepresentation: MouseArea {
        // Sem tamanho próprio o ícone fica com largura zero no painel.
        Layout.minimumWidth: Kirigami.Units.iconSizes.smallMedium
        Layout.minimumHeight: Kirigami.Units.iconSizes.smallMedium
        Layout.preferredWidth: Math.max(height, Kirigami.Units.iconSizes.smallMedium)
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: function(mouse) {
            if (mouse.button === Qt.MiddleButton) { /* ação rápida */ }
            else root.expanded = !root.expanded
        }
        // Nome de ícone do tema; confira se existe (o Breeze não tem "lightbulb", por exemplo).
        Kirigami.Icon { anchors.fill: parent; source: "preferences-desktop-color" }
    }

    // Menu que abre ao clicar (ou o próprio widget, na área de trabalho)
    fullRepresentation: ColumnLayout {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 20
        Layout.preferredWidth: Kirigami.Units.gridUnit * 21
        Layout.preferredHeight: Kirigami.Units.gridUnit * 30
        Kirigami.Heading { level: 3; text: "Meu widget" }
        PlasmaComponents.Label { text: "Conteúdo" }
    }
}
```

Regras:

- Não force `preferredRepresentation`. Sem isso o Plasma escolhe sozinho: compacto no painel,
  completo na área de trabalho.
- Use `Kirigami.Theme.*` para cores e `Kirigami.Units.*` para tamanhos e durações. Assim o
  widget acompanha o tema claro/escuro e a escala da tela.
- Ícone próprio que deve seguir a cor do tema: `Kirigami.Icon { source: Qt.resolvedUrl("../icons/x.svg"); isMask: true; color: ... }`.

## Configurações

`contents/config/main.xml` declara as chaves:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<kcfg xmlns="http://www.kde.org/standards/kcfg/1.0"
      xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
      xsi:schemaLocation="http://www.kde.org/standards/kcfg/1.0
      http://www.kde.org/standards/kcfg/1.0/kcfg.xsd">
  <kcfgfile name=""/>
  <group name="General">
    <entry name="refreshInterval" type="Int"><default>30</default></entry>
    <entry name="demoMode" type="Bool"><default>false</default></entry>
    <entry name="favoriteColors" type="String"><default></default></entry>
  </group>
</kcfg>
```

`contents/config/config.qml` lista as páginas:

```qml
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory { name: "Geral"; icon: "configure"; source: "configGeneral.qml" }
}
```

`contents/ui/configGeneral.qml` liga cada chave a um controle por `cfg_<chave>`:

```qml
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    property alias cfg_refreshInterval: refreshSpin.value
    property alias cfg_demoMode: demoCheck.checked
    property string cfg_favoriteColors: ""   // chave sem controle: declare mesmo assim

    QQC2.SpinBox { id: refreshSpin; Kirigami.FormData.label: "Atualizar a cada (s):"; from: 10; to: 600 }
    QQC2.CheckBox { id: demoCheck; Kirigami.FormData.label: "Demonstração:" }
}
```

No `main.qml` leia com `Plasmoid.configuration.refreshInterval`. Também dá para gravar
(`Plasmoid.configuration.favoriteColors = "..."`), o que serve para guardar estado pequeno
do usuário. Para listas e mapas, grave uma string (separada por vírgula ou JSON).

Mudou o `main.xml`? Só vale depois de reiniciar o `plasmashell`.

## Chamar um script externo

QML não fala com a rede local nem com bibliotecas Python. O padrão é deixar a lógica num
script em `contents/code/` que imprime uma linha JSON, e chamar pelo motor `executable`:

```qml
import org.kde.plasma.plasma5support as P5Support

readonly property string scriptPath:
    Qt.resolvedUrl("../code/ponte.py").toString().replace("file://", "")
property int nonce: 0

function sh(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

function run(args) {
    var cmd = "python3 " + sh(scriptPath)
    for (var i = 0; i < args.length; i++) cmd += " " + sh(args[i])
    nonce++
    executable.connectSource(cmd + " # " + nonce)
}

P5Support.DataSource {
    id: executable
    engine: "executable"
    connectedSources: []
    onNewData: function(source, data) {
        disconnectSource(source)
        var out = (data["stdout"] || "").trim()
        // JSON.parse(out) dentro de try/catch; mostre data["stderr"] se vier vazio
    }
}
```

Pontos que deram problema:

- **Comando repetido não roda de novo.** A fonte é identificada pelo texto do comando. O
  `# nonce` no fim torna cada chamada única.
- **Sempre escape os argumentos** com a função `sh` acima. Nome com espaço ou aspas quebra o
  comando sem ela.
- **`~` não expande** dentro de aspas simples. Troque `~/` por `"$HOME"/` ao montar o comando.
- **Dependência Python:** use um venv fora do repo e guarde o caminho do interpretador numa
  chave de configuração. O `plasmashell` não herda o ambiente do seu terminal.
- **Atualização periódica:** um `Timer` com `triggeredOnStart: true`. Use intervalo curto com
  o menu aberto (`root.expanded`) e longo com ele fechado.
- **Resposta otimista:** mude a tela na hora do clique e deixe a resposta do script confirmar.
  Sem isso cada toque parece travar por um ou dois segundos.

Para notificações do sistema: `import org.kde.notification` e
`Notification { componentName: "plasma_workspace"; eventId: "notification" }`, depois
`title`, `text`, `iconName` e `sendEvent()`.

## Instalar, recarregar e testar

Instalar à mão:

```bash
kpackagetool6 --type Plasma/Applet --install ./org.exemplo.meuwidget
kpackagetool6 --type Plasma/Applet --upgrade ./org.exemplo.meuwidget
kpackagetool6 --type Plasma/Applet --show org.exemplo.meuwidget
```

Durante o desenvolvimento é mais prático um symlink, que dispensa reinstalar a cada mudança:

```bash
ln -sfn "$PWD/org.exemplo.meuwidget" ~/.local/share/plasma/plasmoids/org.exemplo.meuwidget
```

Ciclo de teste:

| O quê | Comando |
|---|---|
| Erros de QML sem abrir nada | `scripts/reload.sh <Id> --no-restart` (acha o `qmllint` do Qt 6, cujo nome e pasta mudam por distro) |
| Ver o widget numa janela | `plasmawindowed org.exemplo.meuwidget` |
| Ver num visualizador | `plasmoidviewer -a ./org.exemplo.meuwidget` |
| Carregar o código novo no painel | `systemctl --user restart plasma-plasmashell` |
| Erros em tempo de execução | `journalctl --user -u plasma-plasmashell --since "2 min ago" \| grep -i meuwidget` |
| Widget não aparece na lista | `kbuildsycoca6`, depois reinicie o `plasmashell` |

O `plasmashell` guarda o QML em memória: editar o arquivo não muda o widget já carregado.
O `qmllint` avisa "Unqualified access" para quase tudo e não entende `ListView.onAdd`; esses
avisos podem ser ignorados. Erros (`Error`) e "property already exists" não.

Capturar a tela para conferir: `spectacle -b -n -a -o saida.png` pega a janela ativa (útil
junto com o `plasmawindowed`).

## Colocar no painel por script

O Plasma aceita JavaScript pelo D-Bus. Use `busctl`, que vem com o systemd (o `qdbus6` nem sempre
está instalado). O `scripts/panel.sh` embrulha os casos comuns:

```bash
busctl --user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript s \
  'var p = panels()[0]; p.addWidget("org.exemplo.meuwidget")'
```

Use `print(...)` no script para devolver texto; o valor da última expressão não volta.

Outros trechos úteis:

```js
// listar widgets do painel
var p = panels()[0]; p.widgetIds.forEach(function(i){ print(i + ":" + p.widgetById(i).type + " ") })
// remover um widget pelo id
panels()[0].widgetById(89).remove()
// ler e gravar configuração de um widget
var w = desktops()[0].widgetById(88); w.currentConfigGroup = ["General"];
w.writeConfig("demoMode", true); w.reloadConfig()
```

Cuidados:

- **A posição no painel não é controlável por script** (não achei como). Ajuste arrastando no
  modo de edição do painel.
- **Depois de `remove()` ou `addWidget()`, espere alguns segundos antes de reiniciar o
  `plasmashell`.** Reiniciar logo em seguida deixa o widget duplicado, porque a
  mudança ainda não tinha sido gravada. Confira com
  `grep -c "plugin=org.exemplo.meuwidget" ~/.config/plasma-org.kde.plasma.desktop-appletsrc`.
