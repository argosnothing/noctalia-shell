import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons
import qs.Services.Compositor
import qs.Services.UI
import qs.Widgets

Rectangle {
  id: root

  property ShellScreen screen

  // Widget properties passed from Bar.qml for per-instance settings
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  readonly property bool isVerticalBar: Settings.data.bar.position === "left" || Settings.data.bar.position === "right"
  readonly property string density: Settings.data.bar.density
  readonly property real itemSize: (density === "compact") ? Style.capsuleHeight * 0.9 : Style.capsuleHeight * 0.8

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId]
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0) {
      var widgets = Settings.data.bar.widgets[section];
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex];
      }
    }
    return {};
  }

  property bool hasWindow: false
  readonly property string hideMode: (widgetSettings.hideMode !== undefined) ? widgetSettings.hideMode : widgetMetadata.hideMode
  readonly property bool onlySameOutput: (widgetSettings.onlySameOutput !== undefined) ? widgetSettings.onlySameOutput : widgetMetadata.onlySameOutput
  readonly property bool onlyActiveWorkspaces: (widgetSettings.onlyActiveWorkspaces !== undefined) ? widgetSettings.onlyActiveWorkspaces : widgetMetadata.onlyActiveWorkspaces
  readonly property bool showTitles: (widgetSettings.showTitles !== undefined) ? widgetSettings.showTitles : widgetMetadata.showTitles

  property real centerSectionX: 0
  property real centerSectionWidth: 0
  property real rightSectionX: 0
  property var hiddenTitleIndices: ({})

  // Context menu state
  property var selectedWindow: null
  property string selectedAppName: ""

  NPopupContextMenu {
    id: contextMenu
    model: {
      var items = [];
      if (selectedWindow) {
        items.push({
                     "label": I18n.tr("context-menu.activate-app", {
                                        "app": selectedAppName
                                      }),
                     "action": "activate",
                     "icon": "focus"
                   });
        items.push({
                     "label": I18n.tr("context-menu.close-app", {
                                        "app": selectedAppName
                                      }),
                     "action": "close",
                     "icon": "x"
                   });
      }
      items.push({
                   "label": I18n.tr("context-menu.widget-settings"),
                   "action": "widget-settings",
                   "icon": "settings"
                 });
      return items;
    }
    onTriggered: action => {
                   if (action === "activate" && selectedWindow) {
                     CompositorService.focusWindow(selectedWindow);
                   } else if (action === "close" && selectedWindow) {
                     CompositorService.closeWindow(selectedWindow);
                   } else if (action === "widget-settings") {
                     BarService.openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings);
                   }
                   selectedWindow = null;
                   selectedAppName = "";
                 }
  }

  function updateHasWindow() {
    try {
      var total = CompositorService.windows.count || 0;
      var activeIds = CompositorService.getActiveWorkspaces().map(function (ws) {
        return ws.id;
      });
      var found = false;
      for (var i = 0; i < total; i++) {
        var w = CompositorService.windows.get(i);
        if (!w)
          continue;
        var passOutput = (!onlySameOutput) || (w.output == screen.name);
        var passWorkspace = (!onlyActiveWorkspaces) || (activeIds.includes(w.workspaceId));
        if (passOutput && passWorkspace) {
          found = true;
          break;
        }
      }
      hasWindow = found;
    } catch (e) {
      hasWindow = false;
    }
  }

  function checkCollision() {
    if (!showTitles || isVerticalBar || section !== "left") {
      hiddenTitleIndices = {};
      return;
    }

    var collisionBoundary = 0;
    if (centerSectionWidth > 0 && centerSectionX > 0) {
      collisionBoundary = centerSectionX - Style.marginS;
    } else if (rightSectionX > 0) {
      collisionBoundary = rightSectionX - Style.marginS;
    } else {
      hiddenTitleIndices = {};
      return;
    }

    var visibleItems = [];
    for (var i = 0; i < taskbarLayout.children.length; i++) {
      var repeater = taskbarLayout.children[i];
      if (repeater && repeater.count !== undefined) {
        for (var j = 0; j < repeater.count; j++) {
          var item = repeater.itemAt(j);
          if (item && item.visible) {
            visibleItems.push({index: j, item: item});
          }
        }
        break;
      }
    }

    if (visibleItems.length === 0) {
      hiddenTitleIndices = {};
      return;
    }

    var newHidden = {};
    var currentWidth = taskbarLayout.x + Style.marginM;
    
    for (var k = 0; k < visibleItems.length; k++) {
      var vItem = visibleItems[k];
      var itemWidth = vItem.item.shouldShowTitle ? (vItem.item.contentLayout.implicitWidth + Style.marginS * 2) : root.itemSize;
      
      if (currentWidth + itemWidth > collisionBoundary) {
        for (var m = visibleItems.length - 1; m >= k; m--) {
          newHidden[visibleItems[m].index] = true;
        }
        break;
      }
      currentWidth += itemWidth + taskbarLayout.spacing;
    }

    hiddenTitleIndices = newHidden;
  }

  Connections {
    target: CompositorService
    function onWindowListChanged() {
      updateHasWindow();
      Qt.callLater(checkCollision);
    }
    function onWorkspaceChanged() {
      updateHasWindow();
      Qt.callLater(checkCollision);
    }
  }

  Component.onCompleted: {
    updateHasWindow();
    Qt.callLater(checkCollision);
  }
  onScreenChanged: {
    updateHasWindow();
    Qt.callLater(checkCollision);
  }
  onCenterSectionXChanged: Qt.callLater(checkCollision)
  onCenterSectionWidthChanged: Qt.callLater(checkCollision)
  onRightSectionXChanged: Qt.callLater(checkCollision)

  // "visible": Always Visible, "hidden": Hide When Empty, "transparent": Transparent When Empty
  visible: hideMode !== "hidden" || hasWindow
  opacity: (hideMode !== "transparent" || hasWindow) ? 1.0 : 0
  Behavior on opacity {
    NumberAnimation {
      duration: Style.animationNormal
      easing.type: Easing.OutCubic
    }
  }

  implicitWidth: visible ? (isVerticalBar ? Style.capsuleHeight : Math.round((showTitles && !isVerticalBar ? taskbarLayout.implicitWidth : taskbarLayoutGrid.implicitWidth) + Style.marginM * 2)) : 0
  implicitHeight: visible ? (isVerticalBar ? Math.round((showTitles && !isVerticalBar ? taskbarLayout.implicitHeight : taskbarLayoutGrid.implicitHeight) + Style.marginM * 2) : Style.capsuleHeight) : 0
  radius: showTitles && !isVerticalBar ? 0 : Style.radiusM
  color: showTitles && !isVerticalBar ? Color.transparent : Style.capsuleColor

  Flow {
    id: taskbarLayout
    visible: showTitles && !isVerticalBar
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    anchors.leftMargin: isVerticalBar ? 0 : Style.marginM

    spacing: Style.marginXXS
    flow: isVerticalBar ? Flow.TopToBottom : Flow.LeftToRight

    Repeater {
      model: CompositorService.windows
      delegate: Rectangle {
        id: taskbarItem
        required property var modelData
        required property int index
        property ShellScreen screen: root.screen
        property bool shouldShowTitle: showTitles && !isVerticalBar && !root.hiddenTitleIndices[index]

        visible: (!onlySameOutput || modelData.output == screen.name) && (!onlyActiveWorkspaces || CompositorService.getActiveWorkspaces().map(function (ws) {
          return ws.id;
        }).includes(modelData.workspaceId))

        width: shouldShowTitle ? contentLayout.implicitWidth + Style.marginS * 2 : root.itemSize
        height: Style.capsuleHeight

        radius: Style.radiusM
        color: Style.capsuleColor

        Behavior on width {
          NumberAnimation {
            duration: Style.animationNormal
            easing.type: Easing.OutCubic
          }
        }

        onWidthChanged: Qt.callLater(root.checkCollision)

        RowLayout {
          id: contentLayout
          anchors.fill: parent
          anchors.leftMargin: Style.marginS
          anchors.rightMargin: Style.marginS
          spacing: Style.marginXXS

          IconImage {
            id: appIcon
            Layout.preferredWidth: root.itemSize - Style.marginS * 2
            Layout.preferredHeight: root.itemSize - Style.marginS * 2
            source: ThemeIcons.iconForAppId(taskbarItem.modelData.appId)
            smooth: true
            asynchronous: true
            opacity: modelData.isFocused ? Style.opacityFull : 0.6

            // Apply dock shader to all taskbar icons
            layer.enabled: widgetSettings.colorizeIcons !== false
            layer.effect: ShaderEffect {
              property color targetColor: Settings.data.colorSchemes.darkMode ? Color.mOnSurface : Color.mSurfaceVariant
              property real colorizeMode: 0.0 // Dock mode (grayscale)

              fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/appicon_colorize.frag.qsb")
            }
          }

          NText {
            id: titleText
            visible: taskbarItem.shouldShowTitle
            Layout.fillWidth: true
            text: taskbarItem.modelData.title || taskbarItem.modelData.appId || "Unknown"
            pointSize: Style.fontSizeS
            applyUiScale: false
            font.weight: Style.fontWeightMedium
            color: Color.mOnSurface
            opacity: modelData.isFocused ? Style.opacityFull : 0.6
          }
        }

        Rectangle {
          id: iconBackground
          visible: !showTitles
          anchors.bottomMargin: -2
          anchors.bottom: parent.bottom
          anchors.horizontalCenter: parent.horizontalCenter
          width: 4
          height: 4
          color: modelData.isFocused ? Color.mPrimary : Color.transparent
          radius: width * 0.5
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          acceptedButtons: Qt.LeftButton | Qt.RightButton

          onPressed: function (mouse) {
            if (!taskbarItem.modelData)
              return;
            if (mouse.button === Qt.LeftButton) {
              try {
                CompositorService.focusWindow(taskbarItem.modelData);
              } catch (error) {
                Logger.e("Taskbar", "Failed to activate toplevel: " + error);
              }
            } else if (mouse.button === Qt.RightButton) {
              TooltipService.hide();
              root.selectedWindow = taskbarItem.modelData;
              root.selectedAppName = CompositorService.getCleanAppName(taskbarItem.modelData.appId, taskbarItem.modelData.title);
              var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
              if (popupMenuWindow) {
                const pos = BarService.getContextMenuPosition(taskbarItem, contextMenu.implicitWidth, contextMenu.implicitHeight);
                contextMenu.openAtItem(taskbarItem, pos.x, pos.y);
                popupMenuWindow.showContextMenu(contextMenu);
              }
            }
          }
          onEntered: TooltipService.show(taskbarItem, taskbarItem.modelData.title || taskbarItem.modelData.appId || "Unknown app.", BarService.getTooltipDirection())
          onExited: TooltipService.hide()
        }
      }
    }
  }

  GridLayout {
    id: taskbarLayoutGrid
    visible: !showTitles || isVerticalBar
    anchors.fill: parent
    anchors {
      leftMargin: isVerticalBar ? undefined : Style.marginM
      rightMargin: isVerticalBar ? undefined : Style.marginM
      topMargin: (density === "compact") ? 0 : isVerticalBar ? Style.marginM : undefined
      bottomMargin: (density === "compact") ? 0 : isVerticalBar ? Style.marginM : undefined
    }

    rows: isVerticalBar ? -1 : 1
    columns: isVerticalBar ? 1 : -1

    rowSpacing: isVerticalBar ? Style.marginXXS : 0
    columnSpacing: isVerticalBar ? 0 : Style.marginXXS

    Repeater {
      model: CompositorService.windows
      delegate: Item {
        id: taskbarItemGrid
        required property var modelData
        property ShellScreen screen: root.screen

        visible: (!onlySameOutput || modelData.output == screen.name) && (!onlyActiveWorkspaces || CompositorService.getActiveWorkspaces().map(function (ws) {
          return ws.id;
        }).includes(modelData.workspaceId))

        Layout.preferredWidth: root.itemSize
        Layout.preferredHeight: root.itemSize
        Layout.alignment: Qt.AlignCenter

        IconImage {
          id: appIcon
          width: parent.width
          height: parent.height
          source: ThemeIcons.iconForAppId(taskbarItemGrid.modelData.appId)
          smooth: true
          asynchronous: true
          opacity: modelData.isFocused ? Style.opacityFull : 0.6

          // Apply dock shader to all taskbar icons
          layer.enabled: widgetSettings.colorizeIcons !== false
          layer.effect: ShaderEffect {
            property color targetColor: Settings.data.colorSchemes.darkMode ? Color.mOnSurface : Color.mSurfaceVariant
            property real colorizeMode: 0.0 // Dock mode (grayscale)

            fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/appicon_colorize.frag.qsb")
          }

          Rectangle {
            id: iconBackground
            anchors.bottomMargin: -2
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: 4
            height: 4
            color: modelData.isFocused ? Color.mPrimary : Color.transparent
            radius: width * 0.5
          }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          acceptedButtons: Qt.LeftButton | Qt.RightButton

          onPressed: function (mouse) {
            if (!taskbarItemGrid.modelData)
              return;
            if (mouse.button === Qt.LeftButton) {
              try {
                CompositorService.focusWindow(taskbarItemGrid.modelData);
              } catch (error) {
                Logger.e("Taskbar", "Failed to activate toplevel: " + error);
              }
            } else if (mouse.button === Qt.RightButton) {
              TooltipService.hide();
              root.selectedWindow = taskbarItemGrid.modelData;
              root.selectedAppName = CompositorService.getCleanAppName(taskbarItemGrid.modelData.appId, taskbarItemGrid.modelData.title);
              var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
              if (popupMenuWindow) {
                const pos = BarService.getContextMenuPosition(taskbarItemGrid, contextMenu.implicitWidth, contextMenu.implicitHeight);
                contextMenu.openAtItem(taskbarItemGrid, pos.x, pos.y);
                popupMenuWindow.showContextMenu(contextMenu);
              }
            }
          }
          onEntered: TooltipService.show(taskbarItemGrid, taskbarItemGrid.modelData.title || taskbarItemGrid.modelData.appId || "Unknown app.", BarService.getTooltipDirection())
          onExited: TooltipService.hide()
        }
      }
    }
  }
}
