import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// Cartão de um item: círculo liga/desliga, nome, estado e uma barra de nível.
// Cuidado com nomes: um id igual a uma propriedade (ex.: id "level") esconde a propriedade,
// e uma propriedade chamada "color" colide com a do Rectangle.
Rectangle {
    id: row

    property string name
    property bool on
    property int level

    signal toggled()
    signal levelMoved(int value)

    readonly property int pad: Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing

    implicitHeight: content.implicitHeight + pad * 2
    radius: Kirigami.Units.cornerRadius * 2.5
    color: on ? Qt.alpha(Kirigami.Theme.highlightColor, 0.12) : Qt.alpha(Kirigami.Theme.textColor, 0.045)
    clip: true
    Behavior on color { ColorAnimation { duration: Kirigami.Units.longDuration } }
    Behavior on implicitHeight { NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic } }

    // Envia só depois que a barra para por um instante (evita uma chamada por pixel).
    Timer {
        id: debounce
        property int val: 0
        interval: 200
        onTriggered: row.levelMoved(val)
    }

    ColumnLayout {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: row.pad }
        spacing: row.pad

        RowLayout {
            Layout.fillWidth: true
            spacing: row.pad

            Rectangle {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 2
                Layout.preferredHeight: Kirigami.Units.gridUnit * 2
                radius: width / 2
                color: row.on ? Kirigami.Theme.highlightColor
                     : Qt.alpha(Kirigami.Theme.textColor, toggleArea.containsMouse ? 0.14 : 0.08)
                scale: toggleArea.pressed ? 0.92 : 1.0
                Behavior on color { ColorAnimation { duration: Kirigami.Units.longDuration } }
                Behavior on scale { NumberAnimation { duration: Kirigami.Units.shortDuration } }
                MouseArea {
                    id: toggleArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: row.toggled()
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: row.name
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: row.on ? Math.round(levelSlider.value) + "%" : "Desligado"
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: 0.65
                }
            }
        }

        PillSlider {
            id: levelSlider
            visible: row.on
            Layout.fillWidth: true
            from: 0; to: 100
            target: row.level            // estado real; o slider segura o valor escolhido
            onMoved: function(v) { debounce.val = v; debounce.restart() }
        }
    }
}
