import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// Botão em forma de pílula, para cenas e opções rápidas.
Rectangle {
    id: chip

    property string text: ""
    property string iconName: ""
    property bool highlighted: false
    signal clicked()

    implicitHeight: Math.round(Kirigami.Units.gridUnit * 1.5)
    implicitWidth: content.implicitWidth + Kirigami.Units.largeSpacing * 2
    radius: height / 2
    color: highlighted ? Qt.alpha(Kirigami.Theme.highlightColor, 0.35)
         : Qt.alpha(Kirigami.Theme.textColor, area.containsMouse ? 0.14 : 0.07)
    scale: area.pressed ? 0.95 : 1.0
    Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
    Behavior on scale { NumberAnimation { duration: Kirigami.Units.shortDuration } }

    RowLayout {
        id: content
        anchors.centerIn: parent
        spacing: Kirigami.Units.smallSpacing
        Kirigami.Icon {
            visible: chip.iconName !== ""
            source: chip.iconName
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
        }
        PlasmaComponents.Label {
            text: chip.text
            font.pointSize: Kirigami.Theme.smallFont.pointSize
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.clicked()
    }
}
