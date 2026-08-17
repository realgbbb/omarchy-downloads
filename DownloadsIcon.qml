import QtQuick
import QtQuick.Shapes
import qs.Commons

// Arrow-into-tray download mark, drawn rather than set from a font so the
// arrow can be animated independently of the tray: when a download lands, the
// arrow drops into the tray twice. Stroke weight scales with `iconSize`, so the
// same component reads correctly at bar size and at hero size.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  // Painted while the arrival animation runs; falls back to `color`.
  property color pulseColor: color

  readonly property bool pulsing: dropAnimation.running
  readonly property color activeColor: pulsing ? pulseColor : color
  readonly property real stroke: Math.max(1, iconSize * 0.11)

  // Driven by the arrival animation; at rest the arrow sits home, fully opaque.
  property real arrowShift: 0
  property real arrowFade: 1.0

  function pulse() {
    dropAnimation.restart()
  }

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  Shape {
    id: tray
    anchors.fill: parent
    antialiasing: true
    layer.enabled: true
    layer.samples: 4

    ShapePath {
      strokeColor: root.activeColor
      strokeWidth: root.stroke
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin

      startX: root.width * 0.16
      startY: root.height * 0.64
      PathLine { x: root.width * 0.16; y: root.height * 0.86 }
      PathLine { x: root.width * 0.84; y: root.height * 0.86 }
      PathLine { x: root.width * 0.84; y: root.height * 0.64 }
    }
  }

  Shape {
    id: arrow
    anchors.fill: parent
    y: root.arrowShift
    opacity: root.arrowFade
    antialiasing: true
    layer.enabled: true
    layer.samples: 4

    ShapePath {
      strokeColor: root.activeColor
      strokeWidth: root.stroke
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin

      startX: root.width * 0.50
      startY: root.height * 0.11
      PathLine { x: root.width * 0.50; y: root.height * 0.60 }
    }

    ShapePath {
      strokeColor: root.activeColor
      strokeWidth: root.stroke
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin

      startX: root.width * 0.28
      startY: root.height * 0.39
      PathLine { x: root.width * 0.50; y: root.height * 0.61 }
      PathLine { x: root.width * 0.72; y: root.height * 0.39 }
    }
  }

  SequentialAnimation {
    id: dropAnimation
    loops: 2
    alwaysRunToEnd: true

    ParallelAnimation {
      NumberAnimation {
        target: root; property: "arrowShift"
        from: -root.height * 0.45; to: 0
        duration: 320; easing.type: Easing.OutCubic
      }
      NumberAnimation {
        target: root; property: "arrowFade"
        from: 0.15; to: 1.0
        duration: 220; easing.type: Easing.OutQuad
      }
    }
    PauseAnimation { duration: 140 }

    onStopped: {
      root.arrowShift = 0
      root.arrowFade = 1.0
    }
  }
}
