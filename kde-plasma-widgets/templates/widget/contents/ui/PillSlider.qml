import QtQuick
import org.kde.kirigami as Kirigami

// Slider em forma de pílula, estilo "ajustes rápidos" do celular.
// Não reage à roda do mouse, para não brigar com a rolagem da lista.
Item {
    id: slider

    property real from: 0
    property real to: 100
    property real value: 0
    // Valor vindo de fora (estado real da lâmpada). Enquanto o usuário mexe, e por um
    // instante depois, ele é ignorado: senão a barra voltaria ao valor antigo antes de
    // a lâmpada confirmar o novo, dando um "vai e volta".
    property real target: 0
    onTargetChanged: if (!area.pressed && !hold.running) value = target
    Component.onCompleted: value = target
    Timer {
        id: hold
        interval: 3000
        onTriggered: slider.value = slider.target
    }
    property color fillColor: Kirigami.Theme.highlightColor
    property string iconName: ""
    // Quando definido, a trilha vira um degradê e o valor é marcado por uma alça.
    property var trackGradient: null
    readonly property bool pressed: area.pressed
    readonly property real position: to > from ? Math.max(0, Math.min(1, (value - from) / (to - from))) : 0

    signal moved(real value)

    implicitHeight: Math.round(Kirigami.Units.gridUnit * 1.25)
    implicitWidth: Kirigami.Units.gridUnit * 10

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: Qt.alpha(Kirigami.Theme.textColor, 0.09)
        gradient: slider.trackGradient
        opacity: slider.trackGradient !== null ? 0.85 : 1
    }

    // Preenchimento (modo brilho)
    Rectangle {
        visible: slider.trackGradient === null
        height: parent.height
        width: Math.max(height, slider.position * parent.width)
        radius: height / 2
        color: slider.fillColor
        Behavior on width { enabled: !area.pressed; NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: Kirigami.Units.longDuration } }
    }

    Kirigami.Icon {
        visible: slider.iconName !== "" && slider.trackGradient === null
        source: slider.iconName
        isMask: true
        color: "#1b1e20"
        opacity: 0.6
        width: Kirigami.Units.iconSizes.small
        height: width
        anchors.verticalCenter: parent.verticalCenter
        x: (parent.height - width) / 2
    }

    // Alça (modo degradê)
    Rectangle {
        visible: slider.trackGradient !== null
        width: parent.height - 4
        height: width
        radius: width / 2
        y: 2
        x: 2 + slider.position * (parent.width - width - 4)
        color: "white"
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.25)
    }

    MouseArea {
        id: area
        anchors.fill: parent
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        function update(mx) {
            var p = Math.max(0, Math.min(1, mx / width))
            var v = Math.round(slider.from + p * (slider.to - slider.from))
            hold.restart()
            if (v !== slider.value) {
                slider.value = v
                slider.moved(v)
            }
        }
        onPressed: function(mouse) { update(mouse.x) }
        onPositionChanged: function(mouse) { if (pressed) update(mouse.x) }
        onWheel: function(wheel) { wheel.accepted = false }
    }
}
