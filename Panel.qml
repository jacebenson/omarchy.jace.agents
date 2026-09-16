import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Every subscription on one screen. A subscription tells you how much of its
// allowance is left and when it comes back; a pay-per-token account tells you
// what is still on the meter. Token history lives in the collectors' records
// for anyone who wants it, but this panel is a balance sheet, not a dashboard.
Panel {
  id: root
  moduleName: "omarchy.agents"
  ipcTarget: "omarchy.agents"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color surface: Color.popups.background
  readonly property color track: Style.selectedFillFor(foreground, Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var providers: usage.enabledProviders

  // A card earns a full row by having something to meter: a credit balance or a
  // rolling window. A provider we can spend money on but cannot read — Fireworks
  // gates its ledger to the dashboard, Claude Code reports nothing until it is
  // signed in, Replicate publishes no balance at all — collapses to just its
  // mark, because a row of empty space says less than a logo that opens the page
  // where the number actually lives. That split is computed, not configured: the
  // day one of them grows an API, its button becomes a row on its own.
  readonly property var meteredProviders: providers.filter(function(p) { return hasFigure(p) })
  readonly property var linkedProviders: providers.filter(function(p) { return !hasFigure(p) })

  function hasFigure(p) {
    return !!p && ((p.limits && p.limits.length > 0) || !!p.balance)
  }

  // Where each provider's real numbers live. This is the one place to edit when
  // a provider moves its billing page; there is nothing to configure, because
  // a dashboard is in the same place for everyone.
  function billingUrl(providerId) {
    var urls = {
      "codex": "https://chatgpt.com/?openaicom_referred=true#settings/Usage",
      "deepseek": "https://platform.deepseek.com/usage",
      "opencode-go": "https://opencode.ai/auth",
      "openrouter": "https://openrouter.ai/settings/credits",
      "fireworks": "https://fireworks.ai/account/billing",
      "claude": "https://claude.ai/settings/usage",
      "replicate": "https://replicate.com/"
    }
    return urls[providerId] || ""
  }

  // The whole card is the link, so a click anywhere on it opens the provider's
  // own page and closes the panel: the dashboard is the only place with the
  // number, and this way there is no second place to look.
  function openBilling(p) {
    if (!p) return
    var url = billingUrl(p.providerId)
    if (url === "") return
    Quickshell.execDetached(["omarchy-launch-browser", url])
    root.close()
  }

  // Countdowns and balances read this instead of Date.now() so the panel keeps
  // telling the truth while it sits open.
  property double nowMs: Date.now()

  // The bar dot answers for the whole list: an allowance or a meter that is
  // nearly gone lights it whichever subscription it belongs to.
  readonly property bool alarming: {
    for (var i = 0; i < providers.length; i++)
      if (providerAlarming(providers[i])) return true
    return false
  }

  function providerAlarming(p) {
    if (!p) return false
    var windows = limitWindows(p)
    for (var i = 0; i < windows.length; i++)
      if (windows[i].percent >= 0.9) return true
    var b = p.balance
    return !!b && b.funded > 0 && b.remaining / b.funded <= 0.1
  }

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  function refreshNow() {
    usage.refreshAll(true)
  }

  function launchAgent() {
    if (root.bar) root.bar.run("omarchy-agent --pick")
    root.close()
  }

  // ----------------------------------------------------------- the column

  function maxScroll() { return Math.max(0, panelFlick.contentHeight - panelFlick.height) }

  function cardItems() {
    var out = []
    var children = column.children
    for (var i = 0; i < children.length; i++)
      if (children[i] && children[i].isProviderCard) out.push(children[i])
    return out
  }

  // `next` walks the list. It used to switch which subscription the panel
  // showed; there is one view now, so it scrolls to the next entry instead —
  // the same muscle memory, and existing keybindings and IPC callers keep
  // working.
  function scrollToNextCard() {
    var cards = cardItems()
    for (var i = 0; i < cards.length; i++) {
      if (cards[i].y > panelFlick.contentY + 4) {
        panelFlick.contentY = clamp(cards[i].y - Style.space(8), 0, maxScroll())
        return
      }
    }
    panelFlick.contentY = 0
  }

  // ---------------------------------------------------------------- limits
  //
  // Collectors report each rolling window in its own words ("Session
  // (5-hour)", "5h window", "Weekly (7-day)"). Everything below normalizes
  // them into one record so the meters speak a single language.

  function windowIsLong(text) {
    return text.indexOf("week") >= 0 || text.indexOf("7-day") >= 0 || text.indexOf("seven") >= 0
      || text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0
  }

  function windowSpanMs(label) {
    var text = String(label || "").toLowerCase()
    if (text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0) return 30 * 24 * 3600 * 1000
    if (windowIsLong(text)) return 7 * 24 * 3600 * 1000
    var hours = text.match(/(\d+)\s*-?\s*h(?:our)?\b/)
    if (hours) return Number(hours[1]) * 3600 * 1000
    var minutes = text.match(/(\d+)\s*-?\s*m(?:in(?:ute)?s?)?\b/)
    if (minutes) return Number(minutes[1]) * 60 * 1000
    return 0
  }

  // A window is named for the span it covers, because that is what tells you
  // whether the 40% you are looking at resets this afternoon or next Tuesday.
  function windowTitle(label) {
    var text = String(label || "").toLowerCase()
    if (text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0) return "30d"
    if (windowIsLong(text)) return "7d"
    var span = windowSpanMs(label)
    if (span > 0) {
      var minutes = Math.round(span / 60000)
      if (minutes < 60) return minutes + "m"
      var hours = Math.round(minutes / 60)
      return hours + "h"
    }
    if (text.indexOf("session") >= 0) return "5h"
    var plain = String(label || "").replace(/\s*\(.*\)\s*/, "").trim()
    return plain === "" ? "Limit" : plain
  }

  // A collector that already knows which window a limit belongs to says so,
  // and that beats reading it back out of the label.
  function limitWindow(label, percent, resetAt, title) {
    return {
      title: String(title || "") !== "" ? String(title) : windowTitle(label),
      percent: Number(percent),
      resetAt: String(resetAt || "")
    }
  }

  function limitWindows(p) {
    if (!p) return []
    var out = []
    var list = p.limits || []
    for (var i = 0; i < list.length; i++) {
      var entry = list[i] || {}
      var percent = Number(entry.percent)
      if (percent >= 0) out.push(limitWindow(entry.label, percent, entry.resetsAt, entry.title))
    }
    return out
  }

  function resetMsFor(w) {
    if (!w || w.resetAt === "") return -1
    var ms = new Date(w.resetAt).getTime()
    return isFinite(ms) ? ms - root.nowMs : -1
  }

  function formatDuration(ms) {
    if (!(ms > 0)) return "now"
    var minutes = Math.floor(ms / 60000)
    var hours = Math.floor(minutes / 60)
    var days = Math.floor(hours / 24)
    // Drop a zero sub-unit: "5h 0m" is noise where "5h" is the whole answer.
    if (days > 0) return hours % 24 > 0 ? days + "d " + (hours % 24) + "h" : days + "d"
    if (hours > 0) return minutes % 60 > 0 ? hours + "h " + (minutes % 60) + "m" : hours + "h"
    return Math.max(1, minutes) + "m"
  }

  // ---------------------------------------------------------------- balance

  function currencyPrefix(currency) {
    var code = String(currency || "USD").toUpperCase()
    if (code === "USD") return "$"
    if (code === "EUR") return "€"
    if (code === "GBP") return "£"
    return code + " "
  }

  function formatMoney(value, currency) {
    var amount = Number(value)
    if (!isFinite(amount)) amount = 0
    return currencyPrefix(currency) + amount.toFixed(2)
  }

  // The line under the name: what this subscription is, and for a prepaid
  // account what it has cost so far. An auth or endpoint problem takes the
  // line over, because that is the more useful thing to know.
  function subText(p) {
    if (!p) return ""
    if (String(p.usageStatusText || "") !== "") return p.usageStatusText
    var b = p.balance
    if (b && b.funded > 0) {
      // A credit balance is what says "prepaid", so the word is dropped and the
      // money keeps its room: an elided "of $90…" reads as $90 or $900.
      var spent = formatMoney(b.spent, b.currency) + " spent of " + formatMoney(b.funded, b.currency)
      return b.estimated ? spent + " · estimated" : spent
    }
    var tier = String(p.tierLabel || "")
    if (tier === "") tier = "Subscription"
    return tier.charAt(0).toUpperCase() + tier.slice(1)
  }

  // Marks resolve by convention, so a new agent's data file needs nothing from
  // this panel: assets/<id>.svg if it ships one, the module's bar glyph if it
  // doesn't. A white mark carries an assets/<id>-light.svg twin for light
  // surfaces, so the luminance check decides which candidate to try first.
  function colorChannelLuminance(value) {
    var channel = Number(value)
    if (!isFinite(channel)) return 0
    return channel <= 0.03928 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4)
  }

  function colorLuminance(color) {
    return 0.2126 * colorChannelLuminance(color.r)
      + 0.7152 * colorChannelLuminance(color.g)
      + 0.0722 * colorChannelLuminance(color.b)
  }

  function iconCandidatesForProvider(p, surfaceColor) {
    if (!p) return []
    var candidates = []
    if (colorLuminance(surfaceColor || Color.background) >= 0.5)
      candidates.push(Qt.resolvedUrl("assets/" + p.providerId + "-light.svg"))
    candidates.push(Qt.resolvedUrl("assets/" + p.providerId + ".svg"))
    return candidates
  }

  // Only speaks up when the numbers cover more than this machine.
  function syncFooter() {
    if (usage.syncStatusText !== "") return usage.syncStatusText
    var devices = usage.aggregateData && usage.aggregateData.deviceCount ? Number(usage.aggregateData.deviceCount) : 0
    if (devices > 0) return "Merged from " + devices + " device" + (devices === 1 ? "" : "s")
    return ""
  }

  // Nothing to report, nothing in the bar: Bar.qml collapses a slot whose item
  // is invisible, so the icon appears the moment the first scan finds usage and
  // stays away entirely on a machine that has never run an agent.
  visible: providers.length > 0
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    nowMs = Date.now()
    if (panelFlick) panelFlick.contentY = 0
    usage.refreshLimits()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Main {
    id: usage
    settings: root.settings
  }

  // Cheap enough to keep running: it only re-evaluates text bindings, and a
  // stale "resets in 2h" on a panel that is open is worse than a timer.
  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshNow(); return "ok" }
    function next(): string { root.scrollToNextCard(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󱚣"
    active: root.alarming
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.launchAgent()
      else if (buttonCode === Qt.MiddleButton) root.scrollToNextCard()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (dy !== 0)
          panelFlick.contentY = root.clamp(panelFlick.contentY + dy * Style.space(56), 0, root.maxScroll())
      }
      onActivateRequested: root.refreshNow()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r" || t === "R") root.refreshNow() }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(8)

          Text {
            visible: root.providers.length === 0
            width: parent.width
            topPadding: Style.space(24)
            text: "No AI coding subscriptions found.\nAgents show up here once you've used them."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          Repeater {
            model: root.meteredProviders

            ProviderRow {
              provider: modelData
            }
          }

          PanelSeparator {
            visible: root.linkedProviders.length > 0 && root.meteredProviders.length > 0
            foreground: root.foreground
          }

          // The providers whose numbers we cannot read: marks only, each one a
          // link to the page that has them.
          Row {
            id: linkedRow
            visible: root.linkedProviders.length > 0
            width: parent.width
            spacing: Style.spacing.md

            readonly property real cellWidth: root.linkedProviders.length > 0
              ? (width - spacing * (root.linkedProviders.length - 1)) / root.linkedProviders.length
              : 0

            Repeater {
              model: root.linkedProviders

              LinkedProviderButton {
                required property var modelData
                width: linkedRow.cellWidth
                provider: modelData
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: text !== ""
            width: parent.width
            topPadding: Style.space(4)
            text: root.syncFooter()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  // A provider's mark, or the bar glyph when it ships none. Shared by the rows
  // and the linked buttons so the asset-resolution convention lives in one
  // place: assets/<id>.svg for dark surfaces, an <id>-light.svg twin for light
  // ones, the module glyph as the last resort.
  component ProviderMark: Item {
    id: markRoot
    property var provider: null
    property real markSize: Style.font.display

    width: markSize
    height: markSize

    readonly property var candidates: root.iconCandidatesForProvider(provider, root.surface)
    // Provider objects are rebuilt on every refresh, which churns the array's
    // identity without changing its content. Restart the fallback walk only
    // when the URLs change: re-pointing source at a URL whose load already
    // failed emits no statusChanged, so an identity-only reset would strand the
    // walker on a missing -light twin.
    property string candidatesKey: candidates.join("\n")
    property int candidateIndex: 0
    onCandidatesKeyChanged: candidateIndex = 0

    Image {
      id: markImage
      anchors.fill: parent
      source: markRoot.candidateIndex < markRoot.candidates.length ? markRoot.candidates[markRoot.candidateIndex] : ""
      sourceSize.width: markRoot.markSize * 2
      sourceSize.height: markRoot.markSize * 2
      fillMode: Image.PreserveAspectFit
      // Advancing source from inside its own status change trips the
      // binding-loop detector; defer the step one tick.
      onStatusChanged: if (status === Image.Error && markRoot.candidateIndex < markRoot.candidates.length)
        Qt.callLater(function() { markRoot.candidateIndex++ })
    }

    Text {
      textFormat: Text.PlainText
      anchors.centerIn: parent
      visible: markImage.status !== Image.Ready
      text: button.text
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: markRoot.markSize
    }
  }

  // One subscription, one line: what it is, and either what is left on the
  // meter or how much of the allowance is gone and when it comes back.
  component ProviderRow: Item {
    id: providerRow
    property var provider: null
    // Marks this item for the column walker, which has no other way to tell a
    // row apart from the empty-state text.
    property bool isProviderCard: true

    readonly property var limits: root.limitWindows(provider)
    readonly property var balance: provider ? (provider.balance || null) : null
    readonly property bool hasStatus: String(provider ? provider.usageStatusText : "") !== ""
    readonly property bool balanceAlarming: !!balance && balance.funded > 0
      && balance.remaining / balance.funded <= 0.1

    // The fullest window is the one that will stop the next prompt, so it keeps
    // full contrast while the rest recede.
    readonly property real bindingPercent: {
      var best = -1
      for (var i = 0; i < limits.length; i++) best = Math.max(best, limits[i].percent)
      return best
    }

    readonly property real balanceRatio: balance && balance.funded > 0
      ? root.clamp(balance.remaining / balance.funded, 0, 1)
      : -1

    // The active block on the right. A row only exists when it has a figure, so
    // this is either the balance or the window list; a status line takes the
    // name column instead and leaves this empty.
    readonly property var trailingBlock: hasStatus
      ? null
      : (balance ? balanceBlock : windowColumn)

    width: parent ? parent.width : implicitWidth
    implicitHeight: Math.max(Style.font.display, labels.implicitHeight, trailing.height) + Style.spacing.xl

    readonly property bool hovered: rowHover.containsMouse

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, providerRow.hovered ? 0.09 : 0.04)

      Behavior on color { ColorAnimation { duration: 120 } }
    }

    ProviderMark {
      id: mark
      provider: providerRow.provider
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.xl
      anchors.verticalCenter: parent.verticalCenter
    }

    // ---------- name and plan ----------
    Column {
      id: labels
      anchors.left: mark.right
      anchors.leftMargin: Style.space(14)
      anchors.right: trailing.left
      anchors.rightMargin: Style.spacing.md
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Text {
        id: nameText
        textFormat: Text.PlainText
        width: parent.width
        text: providerRow.provider ? providerRow.provider.providerName : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        id: subLine
        textFormat: Text.PlainText
        width: parent.width
        text: root.subText(providerRow.provider)
        color: providerRow.hasStatus ? root.urgent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    // ---------- balance or allowance ----------
    Item {
      id: trailing
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.xl
      anchors.verticalCenter: parent.verticalCenter
      width: providerRow.trailingBlock ? providerRow.trailingBlock.width : 0
      height: providerRow.trailingBlock ? providerRow.trailingBlock.height : 0

      Column {
        id: balanceBlock
        visible: !providerRow.hasStatus && !!providerRow.balance
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)

        Text {
          id: balanceValue
          textFormat: Text.PlainText
          anchors.right: parent.right
          text: providerRow.balance
            ? root.formatMoney(providerRow.balance.remaining, providerRow.balance.currency)
            : ""
          color: providerRow.balanceAlarming ? root.urgent : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Meter {
          id: balanceMeter
          visible: providerRow.balanceRatio >= 0
          width: Style.space(96)
          // Collapse the rail when there is no funded figure to draw it
          // against, so an unknown total costs no vertical space.
          thickness: providerRow.balanceRatio >= 0
            ? Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))
            : 0
          value: providerRow.balanceRatio
          alarming: providerRow.balanceAlarming
        }
      }

      Column {
        id: windowColumn
        visible: !providerRow.hasStatus && !providerRow.balance && providerRow.limits.length > 0
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)

        Repeater {
          model: providerRow.limits

          LimitLine {
            required property var modelData
            window: modelData
            primary: modelData.percent >= providerRow.bindingPercent
          }
        }
      }
    }

    // The whole card is the link. A provider whose numbers we cannot read still
    // has a dashboard that knows them, and this is the shortest path to it.
    MouseArea {
      id: rowHover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.openBilling(providerRow.provider)
    }

    PanelToolTip {
      visible: rowHover.containsMouse && root.billingUrl(providerRow.provider ? providerRow.provider.providerId : "") !== ""
      text: "Open " + (providerRow.provider ? providerRow.provider.providerName : "") + " billing"
      fontFamily: root.fontFamily
    }
  }

  // A provider we can spend money on but cannot read: Fireworks gates its
  // ledger to the dashboard, Claude Code reports nothing until it is signed in,
  // Replicate publishes no balance at all. No row can say anything useful, so
  // it is just the mark — and the whole button opens the page that does know.
  component LinkedProviderButton: Item {
    id: linkedButton
    property var provider: null
    property bool isProviderCard: true

    readonly property bool hovered: buttonHover.containsMouse

    implicitHeight: Style.font.display + Style.spacing.xl

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, linkedButton.hovered ? 0.09 : 0.04)

      Behavior on color { ColorAnimation { duration: 120 } }
    }

    ProviderMark {
      anchors.centerIn: parent
      provider: linkedButton.provider
    }

    MouseArea {
      id: buttonHover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.openBilling(linkedButton.provider)
    }

    // With only a logo on screen, the tooltip carries the name — and any reason
    // the number is missing, so "no data" never looks like a bug.
    PanelToolTip {
      visible: buttonHover.containsMouse
      text: {
        var p = linkedButton.provider
        if (!p) return ""
        var parts = [String(p.providerName || "")]
        var status = String(p.usageStatusText || "")
        if (status !== "") parts.push(status)
        parts.push("open billing")
        return parts.join(" · ")
      }
      fontFamily: root.fontFamily
    }
  }

  // One rolling window: how much of it is gone and when it comes back. Laid
  // out with anchors rather than a Row, because a positioner does not honour
  // per-child vertical centering and the meter is shorter than the text.
  //
  // The bar is the percentage, so the number is not repeated beside it: the
  // row reads "5h ____ 4h 13m" and the label, the bar, and the countdown all
  // line up across windows, which is what makes three of them scannable.
  component LimitLine: Item {
    id: limitLine
    property var window: null
    property bool primary: true

    readonly property real gap: Style.space(6)
    readonly property real labelWidth: Style.space(22)
    readonly property real resetWidth: Style.space(52)
    readonly property real alarming: window ? window.percent >= 0.9 : false

    // Fixed so every window's bar starts and ends on the same edge.
    width: Style.space(150)
    implicitWidth: width
    implicitHeight: Math.max(titleLabel.implicitHeight, meter.implicitHeight, resetLabel.implicitHeight)
    height: implicitHeight

    Text {
      id: titleLabel
      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: limitLine.window ? limitLine.window.title : ""
      color: limitLine.primary ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: limitLine.primary
      width: limitLine.labelWidth
    }

    Meter {
      id: meter
      anchors.left: titleLabel.right
      anchors.leftMargin: limitLine.gap
      anchors.right: resetLabel.left
      anchors.rightMargin: limitLine.gap
      anchors.verticalCenter: parent.verticalCenter
      value: limitLine.window ? limitLine.window.percent : -1
      alarming: limitLine.alarming
    }

    Text {
      id: resetLabel
      textFormat: Text.PlainText
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: {
        var remainingMs = root.resetMsFor(limitLine.window)
        return remainingMs > 0 ? root.formatDuration(remainingMs) : ""
      }
      color: limitLine.primary ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignRight
      width: limitLine.resetWidth
    }
  }

  // Rounded track showing the percentage of the allowance used.
  component Meter: Item {
    id: meter
    property real value: -1
    property bool alarming: false
    property real thickness: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))

    implicitHeight: thickness

    Rectangle {
      id: meterTrack
      anchors.fill: parent
      radius: height / 2
      color: root.track
    }

    Rectangle {
      anchors.left: meterTrack.left
      anchors.verticalCenter: meterTrack.verticalCenter
      height: meterTrack.height
      radius: meterTrack.radius
      width: meterTrack.width * root.clamp(meter.value, 0, 1)
      color: meter.alarming ? root.urgent : root.foreground

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }
  }
}
