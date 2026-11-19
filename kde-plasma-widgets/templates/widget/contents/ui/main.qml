import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

// Modelo: ícone no painel que abre um menu com uma lista de itens.
// O estado vem de contents/code/bridge.py, que imprime uma linha JSON por chamada.
PlasmoidItem {
    id: root

    property string errorMsg: ""
    property bool loading: false
    property int nonce: 0
    property var items: []          // último estado, como veio da ponte
    readonly property int activeCount: items.filter(function(i) { return i.on }).length

    readonly property string bridgePath: Qt.resolvedUrl("../code/bridge.py").toString().replace("file://", "")

    toolTipMainText: Plasmoid.title
    toolTipSubText: errorMsg !== "" ? errorMsg : activeCount + " de " + items.length + " ativos"

    ListModel { id: itemModel }

    function sh(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }

    // "~" não expande dentro de aspas simples: troca por "$HOME".
    function shPath(p) {
        return p.indexOf("~/") === 0 ? "\"$HOME\"/" + sh(p.substring(2)) : sh(p)
    }

    // O "# nonce" torna cada comando único; sem ele o mesmo comando não roda duas vezes.
    function run(args) {
        var cmd = shPath(Plasmoid.configuration.pythonPath || "python3") + " " + sh(bridgePath)
        for (var i = 0; i < args.length; i++) cmd += " " + sh(args[i])
        nonce++
        executable.connectSource(cmd + " # " + nonce)
    }

    function refresh() {
        if (loading) return
        loading = true
        run(["status"])
    }

    // Muda a tela na hora; a resposta da ponte confirma o estado real.
    function command(id, verb, value) {
        for (var i = 0; i < items.length; i++) {
            if (items[i].id !== id) continue
            if (verb === "toggle") items[i].on = !items[i].on
            else if (verb === "level") items[i].level = value
        }
        sync()
        run(value === undefined ? [verb, id] : [verb, id, String(value)])
    }

    // Ajusta o modelo no lugar (set/insert/remove). Recriar o modelo destruiria os
    // delegates: perde arraste em andamento e estado de interface.
    function sync() {
        for (var i = 0; i < items.length; i++) {
            var row = { itemId: items[i].id, name: items[i].name || items[i].id,
                        on: !!items[i].on, level: items[i].level || 0 }
            var j = -1
            for (var k = i; k < itemModel.count; k++)
                if (itemModel.get(k).itemId === row.itemId) { j = k; break }
            if (j === i) itemModel.set(i, row)
            else {
                if (j > i) itemModel.remove(j)
                itemModel.insert(i, row)
            }
        }
        while (itemModel.count > items.length) itemModel.remove(itemModel.count - 1)
    }

    // Só a consulta completa substitui a lista; resposta de comando traz só o que mudou.
    function apply(list, full) {
        if (full) items = list
        else {
            var byId = {}
            list.forEach(function(i) { byId[i.id] = i })
            items = items.map(function(i) { return byId[i.id] || i })
        }
        sync()
    }

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            disconnectSource(source)
            root.loading = false
            var out = (data["stdout"] || "").trim()
            if (!out) {
                root.errorMsg = (data["stderr"] || "Sem resposta da ponte").trim()
                return
            }
            try {
                var parsed = JSON.parse(out)
                if (parsed.error) root.errorMsg = parsed.error
                else {
                    root.errorMsg = ""
                    root.apply(parsed.items, source.indexOf("'status' #") >= 0)
                }
            } catch (e) {
                root.errorMsg = "Saída inválida da ponte: " + out.substring(0, 120)
            }
        }
    }

    Timer {
        // Menu aberto: atualiza rápido. Fechado: no intervalo configurado.
        interval: root.expanded ? 5000 : Math.max(5, Plasmoid.configuration.refreshInterval) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    compactRepresentation: MouseArea {
        // Sem tamanho próprio o ícone fica com largura zero no painel.
        Layout.minimumWidth: Kirigami.Units.iconSizes.smallMedium
        Layout.minimumHeight: Kirigami.Units.iconSizes.smallMedium
        Layout.preferredWidth: Math.max(height, Kirigami.Units.iconSizes.smallMedium)
        acceptedButtons: Qt.LeftButton
        onClicked: root.expanded = !root.expanded

        Kirigami.Icon {
            anchors.fill: parent
            source: Qt.resolvedUrl("../icons/icon.svg")
            isMask: true
            color: root.errorMsg !== "" ? Kirigami.Theme.negativeTextColor
                 : (root.activeCount > 0 ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor)
            opacity: root.activeCount > 0 ? 1.0 : 0.6
        }
    }

    fullRepresentation: ColumnLayout {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        Layout.minimumHeight: Kirigami.Units.gridUnit * 10
        Layout.preferredHeight: Kirigami.Units.gridUnit * 22
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing
            Layout.topMargin: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.largeSpacing

            ColumnLayout {
                Layout.fillWidth: true   // empurra os botões para a direita
                spacing: 0
                Kirigami.Heading { Layout.fillWidth: true; level: 3; text: Plasmoid.title }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: 0.65
                    text: root.activeCount + " de " + root.items.length + " ativos"
                }
            }
            PlasmaComponents.ToolButton {
                icon.name: "view-refresh"
                text: "Atualizar"
                display: PlasmaComponents.AbstractButton.IconOnly
                enabled: !root.loading
                onClicked: root.refresh()
                PlasmaComponents.ToolTip { text: "Atualizar" }
            }
        }

        PlasmaComponents.Label {
            visible: root.errorMsg !== ""
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.largeSpacing
            wrapMode: Text.Wrap
            color: Kirigami.Theme.negativeTextColor
            text: root.errorMsg
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 0          // o espaço entre linhas fica dentro de cada linha (ver slot.height)
            boundsBehavior: Flickable.StopAtBounds
            model: itemModel
            // Sem transições da lista: cada linha anima a própria altura (reveal). Misturar
            // transições de "y" com cartões que mudam de altura sobrepõe as linhas.
            delegate: Item {
                id: slot
                required property var model
                property real reveal: 1
                width: list.width
                height: (card.implicitHeight + Kirigami.Units.largeSpacing) * reveal
                opacity: reveal
                clip: reveal < 1
                onHeightChanged: Qt.callLater(list.forceLayout)

                ListView.onAdd: NumberAnimation {
                    target: slot; property: "reveal"; from: 0; to: 1
                    duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic
                }
                ListView.onRemove: SequentialAnimation {
                    PropertyAction { target: slot; property: "ListView.delayRemove"; value: true }
                    NumberAnimation {
                        target: slot; property: "reveal"; to: 0
                        duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic
                    }
                    PropertyAction { target: slot; property: "ListView.delayRemove"; value: false }
                }

                ItemRow {
                    id: card
                    width: slot.width
                    name: slot.model.name
                    on: slot.model.on
                    level: slot.model.level
                    onToggled: root.command(slot.model.itemId, "toggle")
                    onLevelMoved: function(v) { root.command(slot.model.itemId, "level", v) }
                }
            }
        }
    }
}
