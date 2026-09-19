// SPDX-License-Identifier: GPL-3.0-only
pragma ComponentBehavior: Bound

// SDF morph surface: a pill (the search field) that grows four circular mode
// buttons out of its right edge. The motion is authored in QML while the
// connected, liquid-looking shape comes from the fragment shader.
//
// Adapted for the Omarchy shell from the "Spotlight knockoff" by u/Stat_Indet
// (https://github.com/StatIndet/quickshell). Colors are injected by the caller
// so the surface follows the active Omarchy theme.

import QtQuick
import QtQuick.Effects

Item {
    id: root

    required property real railProgress
    required property real mainLeft
    required property real collapsedMainWidth
    required property real expandedMainWidth
    required property real shapeCenterY
    required property real shapeHeight
    required property real buttonDiameter
    required property real buttonGap
    required property real blurEdgeInset

    property int buttonCount: 4
    property color surfaceColor: "#20242a"
    property color shadowColor: "#000000"
    property real shadowBlur: 0.72
    property real shadowVerticalOffset: 7

    // Corner radius of the search field. The mode lobes stay fully round
    // regardless (their radius is derived from their own size in the shader).
    property real mainCornerRadius: shapeHeight * 0.5

    // The pill leads the motion; the trailing buttons follow with progressively
    // slower responses. Continuous damping avoids stops between authored poses, using the
    // original spring responses.
    readonly property real mainWidth: interpolate(collapsedMainWidth, expandedMainWidth, response(0, 6.2, 7.5,
                                                                                                  0.4))
    readonly property real mainCenterX: mainLeft + mainWidth / 2
    readonly property real mainRight: mainLeft + mainWidth
    readonly property real expandedMainRight: mainLeft + expandedMainWidth
    readonly property vector4d mainShape: Qt.vector4d(mainCenterX, shapeCenterY, mainWidth, shapeHeight)
    readonly property var buttonShapes: [buttonShape(0), buttonShape(1), buttonShape(2), buttonShape(3)]
    readonly property var travelDelays: [0.06, 0.036, 0.032]
    readonly property var travelDecays: [7.2, 5.4, 5.4]
    readonly property var travelFrequencies: [8.9, 6.2, 5.35]
    readonly property var growthRates: [3.8, 3.1, 2.7]

    function smoothstep(value) {
        const progress = Math.max(0, Math.min(1, value));
        return progress * progress * (3 - 2 * progress);
    }

    function stage(start, end) {
        return smoothstep((root.railProgress - start) / (end - start));
    }

    function interpolate(from, to, progress) {
        return from + (to - from) * progress;
    }

    // Normalize the damped response at the endpoint so interruption/reversal
    // remains a pure function of railProgress and the final layout is exact.
    function response(delay, decay, frequency, phase) {
        const time = Math.max(0, Math.min(1, root.railProgress) - delay);
        const end = 1 - delay;
        const value = 1 - Math.exp(-decay * time) * (Math.cos(frequency * time) + phase * Math.sin(frequency
                                                                                                   * time));
        const terminal = 1 - Math.exp(-decay * end) * (Math.cos(frequency * end) + phase * Math.sin(frequency
                                                                                                    * end));
        return value / terminal;
    }

    function buttonGrowth(index) {
        if (index >= root.buttonCount) return 0;
        if (index === 0)
            return response(0.055, 10.5, 10.5, 1);
        const rate = root.growthRates[index - 1];
        return response(0, rate, rate, 0);
    }

    function buttonCenterX(index) {
        const diameter = root.buttonDiameter;
        const emergence = diameter * 0.3 * (buttonGrowth(0) - 1);
        const firstCenter = root.expandedMainRight + root.buttonGap + diameter / 2 + emergence;
        if (index === 0)
            return firstCenter;
        const decay = root.travelDecays[index - 1];
        const frequency = root.travelFrequencies[index - 1];
        const travel = response(root.travelDelays[index - 1], decay, frequency, decay / frequency);
        return firstCenter + index * (diameter + root.buttonGap) * travel;
    }

    function buttonShape(index) {
        const diameter = root.buttonDiameter * buttonGrowth(index);
        return Qt.vector4d(buttonCenterX(index), root.shapeCenterY, diameter, diameter);
    }

    function buttonBlend(index) {
        const shape = root.buttonShapes[index];
        // Suppress blending while one lobe is still buried in another; this
        // keeps the pill from inflating as the chain emerges. The same short
        // fade follows each lobe, so receding buttons cannot reconnect later.
        const previous = index === 0 ? root.mainShape : root.buttonShapes[index - 1];
        const previousCenter = index === 0 ? root.mainRight - root.shapeHeight / 2 : previous.x;
        const radii = (Math.min(previous.z, previous.w) + Math.min(shape.z, shape.w)) / 2;
        const separation = radii > 0 ? Math.abs(shape.x - previousCenter) / radii : 0;
        const exposed = smoothstep((separation - 0.5) / 0.5);
        const release = stage(0.27 + index * 0.063, 0.47 + index * 0.063);
        return Math.min(shape.z, shape.w, root.buttonDiameter) * 0.78 * exposed * (1 - release);
    }

    function iconProgress(index) {
        return stage(0.36 + index * 0.025, 0.55 + index * 0.025);
    }

    ShaderEffect {
        id: surfaceSource

        anchors.fill: parent
        visible: false

        property vector2d resolution: Qt.vector2d(width, height)
        // Keep the intermediate texture opaque. MultiEffect's shadow mixing
        // otherwise changes the alpha/color of an already translucent fill.
        property color fillColor: Qt.rgba(root.surfaceColor.r, root.surfaceColor.g, root.surfaceColor.b, 1)
        property vector4d mainShape: root.mainShape
        property real mainRadius: root.mainCornerRadius
        property vector4d button0Shape: root.buttonShapes[0]
        property vector4d button1Shape: root.buttonShapes[1]
        property vector4d button2Shape: root.buttonShapes[2]
        property vector4d button3Shape: root.buttonShapes[3]
        property vector4d blends: Qt.vector4d(root.buttonBlend(0), root.buttonBlend(1), root.buttonBlend(2),
                                              root.buttonBlend(3))

        fragmentShader: Qt.resolvedUrl("assets/spotlight_mode_field.frag.qsb")
    }

    MultiEffect {
        anchors.fill: surfaceSource
        source: surfaceSource
        opacity: root.surfaceColor.a
        autoPaddingEnabled: true
        shadowEnabled: true
        shadowColor: root.shadowColor
        shadowBlur: root.shadowBlur
        shadowVerticalOffset: root.shadowVerticalOffset
        shadowHorizontalOffset: 0
    }
}
