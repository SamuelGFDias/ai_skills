import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Cada chave do main.xml precisa de um cfg_<chave> aqui, mesmo sem controle na tela.
Kirigami.FormLayout {
    property alias cfg_refreshInterval: refreshSpin.value
    property alias cfg_pythonPath: pythonField.text

    QQC2.SpinBox {
        id: refreshSpin
        Kirigami.FormData.label: "Atualizar a cada (s):"
        from: 5
        to: 3600
    }
    QQC2.TextField {
        id: pythonField
        Kirigami.FormData.label: "Interpretador Python:"
        Layout.fillWidth: true
        placeholderText: "python3 ou o python de um venv"
    }
}
