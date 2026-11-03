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
  ipcTarget: "jace.agents"
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
  readonly property var meteredProviders: providers.filter(function(p) { return hasFigure(p) && !isHidden(p) })
  readonly property var linkedProviders: providers.filter(function(p) { return !hasFigure(p) || isHidden(p) })

  function isHidden(p) {
    return !!p && usage.hiddenProviders.indexOf(p.providerId) !== -1
  }

  // Hiding is only offered where it can be undone, and showing only where there
  // is a figure to show: a mark with nothing to report has no card to return to.
  function canHide(p) { return hasFigure(p) && !isHidden(p) }
  function canShow(p) { return hasFigure(p) && isHidden(p) }

  function hasFigure(p) {
    return !!p && ((p.limits && p.limits.length > 0) || !!p.balance)
  }

  // Where each provider's real numbers live. This is the one place to edit when
  // a provider moves its billing page; there is nothing to configure, because a
  // dashboard is in the same place for everyone.
  //
  // Every card the collector can emit needs an entry here, or its details have
  // no link and the only way to the dashboard is gone. The authoritative list
  // of ids is CARD_DEFAULTS in bin/omarchy-agent-usage-opencode, plus `claude`
  // and `fireworks`, which the upstream collectors own.
  function billingUrl(providerId) {
    var urls = {
      "openai": "https://chatgpt.com/?openaicom_referred=true#settings/Usage",
      "openai-api": "https://platform.openai.com/settings/organization/billing/overview",
      "opencode-go": "https://opencode.ai/console",
      "opencode": "https://opencode.ai/auth",
      "deepseek": "https://platform.deepseek.com/usage",
      "openrouter": "https://openrouter.ai/settings/credits",
      "fireworks": "https://fireworks.ai/account/billing",
      "claude": "https://claude.ai/settings/usage",
      "replicate": "https://replicate.com/",
      "github-copilot": "https://github.com/settings/copilot"
    }
    return urls[providerId] || ""
  }

  // The whole card is the link, so a click anywhere on it opens the provider's
  // own page and closes the panel: the dashboard is the only place with the
  // number, and this way there is no second place to look.
  function openBilling(p) {
    if (!p) return
    openUrl(billingUrl(p.providerId))
  }

  function openUrl(url) {
    if (String(url || "") === "") return
    Quickshell.execDetached(["omarchy-launch-browser", url])
    root.close()
  }

  // Which card is showing its details. One at a time: the panel is height
  // capped, and a column of open drawers buries the numbers the panel exists
  // for.
  property string expandedProviderId: ""

  function toggleExpanded(providerId) {
    expandedProviderId = expandedProviderId === String(providerId) ? "" : String(providerId)
  }

  property string fundedError: ""
  property string orderError: ""
  property string apiKeyError: ""
  property string pendingApiKey: ""

  readonly property string collectorPath: localPath(Qt.resolvedUrl("bin/omarchy-agent-usage-opencode"))
  readonly property var apiKeyProviderIds: ["deepseek", "openrouter", "opencode-go", "openai-api"]

  function providerConfigPath(providerId) {
    var configProviders = ["deepseek", "openrouter", "opencode-go", "openai-api", "opencode", "fireworks"]
    if (configProviders.indexOf(String(providerId || "")) === -1) return ""
    var configHome = Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"
    return configHome + "/omarchy/agents/" + String(providerId) + ".json"
  }

  function localPath(url) {
    var text = String(url || "")
    if (text.indexOf("file://") !== 0) return text
    return decodeURIComponent(text.substring(7))
  }

  // Cards whose remaining balance is worked out rather than read: you supply the
  // figure you can see, and the spend comes from a provider API (Fireworks, the
  // OpenAI API platform), or from a balance opencode records but cannot price.
  // It belongs on exactly those cards — Zen used to be here and is not any
  // more, because the OpenCode console reports that balance itself, so a typed
  // number would be a second opinion rather than the answer.
  readonly property var estimatedBalanceProviders: ["fireworks", "opencode", "openai-api"]

  function needsFundedAmount(p) {
    if (!p || estimatedBalanceProviders.indexOf(p.providerId) === -1) return false
    // No balance yet, or one derived from a figure you supplied: both want the
    // field. A spend-only balance carries no funded figure, and the field is
    // exactly how you supply one. The single case that hides it is a live
    // ledger — a balance with a funded figure behind it and no estimate — where
    // a typed number would be a second opinion rather than the answer.
    if (!p.balance) return true
    return p.balance.estimated === true || Number(p.balance.funded || 0) === 0
  }

  // The collector owns these config files, so the panel asks it to write and
  // then refreshes. One writer, no JSON and no paths in the UI.
  function saveFundedAmount(providerId, amount) {
    if (providerId === "" || root.collectorPath === "") return
    fundedError = ""
    setFundedProcess.command = [root.collectorPath, "--set-funded", providerId, amount]
    setFundedProcess.running = true
  }

  function saveApiKey(providerId, key) {
    if (providerId === "" || root.collectorPath === "" || String(key || "") === "") return
    apiKeyError = ""
    pendingApiKey = String(key)
    setApiKeyProcess.command = [root.collectorPath, "--set-api-key", providerId]
    setApiKeyProcess.running = true
  }

  function editProviderFile(providerId) {
    var path = root.providerConfigPath(providerId)
    if (path === "") return
    Quickshell.execDetached(["omarchy-launch-editor", path])
    root.close()
  }

  // Every id this plugin already knows about, rendered or not. A card whose
  // record disappears for a while must keep whatever was decided about it, or
  // hiding something else would quietly un-hide it when the record returns.
  function knownProviderIds() {
    var ids = []
    for (var i = 0; i < providers.length; i++) ids.push(providers[i].providerId)
    var remembered = usage.providerOrder.concat(usage.hiddenProviders)
    for (var j = 0; j < remembered.length; j++)
      if (ids.indexOf(remembered[j]) === -1) ids.push(String(remembered[j]))
    return ids
  }

  function providerById(id) {
    for (var i = 0; i < providers.length; i++)
      if (providers[i].providerId === id) return providers[i]
    return null
  }

  // The cards sharing this one's group, in the order they are drawn. A control
  // that cannot move anything is not shown at all, so this is what decides
  // whether each direction is offered.
  function groupSiblings(p) {
    var siblings = []
    if (!p) return siblings
    var rank = usage.providerRank(p)
    for (var i = 0; i < providers.length; i++)
      if (usage.providerRank(providers[i]) === rank) siblings.push(providers[i])
    return siblings
  }

  function canMoveToTop(p) {
    var siblings = groupSiblings(p)
    return siblings.length > 1 && siblings[0].providerId !== p.providerId
  }

  function canMoveToBottom(p) {
    var siblings = groupSiblings(p)
    return siblings.length > 1 && siblings[siblings.length - 1].providerId !== p.providerId
  }

  // Moving happens inside a group, never across one: the group answers "what
  // can I still lose?", which is the reason the list is in this order at all.
  function moveProvider(p, toTop) {
    if (!p || root.collectorPath === "") return

    var ids = []
    for (var i = 0; i < providers.length; i++) ids.push(providers[i].providerId)

    var at = ids.indexOf(p.providerId)
    if (at === -1) return
    ids.splice(at, 1)

    // Land on the first or last sibling still in the list.
    var insertAt = ids.length
    for (var j = 0; j < ids.length; j++) {
      var sibling = root.providerById(ids[j])
      if (!sibling || usage.providerRank(sibling) !== usage.providerRank(p)) continue
      insertAt = toTop ? j : j + 1
      if (toTop) break
    }
    ids.splice(insertAt, 0, p.providerId)

    // Anything not currently drawn keeps its place at the end rather than being
    // dropped from the arrangement.
    var remembered = root.knownProviderIds()
    for (var k = 0; k < remembered.length; k++)
      if (ids.indexOf(remembered[k]) === -1) ids.push(remembered[k])

    orderError = ""
    setOrderProcess.command = [root.collectorPath, "--set-order", ids.join(",")]
    setOrderProcess.running = true
  }

  Process {
    id: setOrderProcess
    running: false
    onExited: function(code) { if (code !== 0) root.orderError = "Could not save" }
  }

  function setHidden(p, hidden) {
    if (!p || root.collectorPath === "") return
    var ids = []
    var known = root.knownProviderIds()
    for (var i = 0; i < known.length; i++) {
      var id = known[i]
      // Decide from the recorded list, not from an object: an id that is not on
      // screen right now still has a state to preserve.
      var wasHidden = usage.hiddenProviders.indexOf(id) !== -1
      if (id === p.providerId ? hidden : wasHidden) ids.push(id)
    }
    orderError = ""
    setHiddenProcess.command = [root.collectorPath, "--set-hidden", ids.join(",")]
    setHiddenProcess.running = true
  }

  Process {
    id: setHiddenProcess
    running: false
    onExited: function(code) { if (code !== 0) root.orderError = "Could not save" }
  }

  Process {
    id: setFundedProcess
    running: false
    onExited: function(code) {
      if (code !== 0) {
        root.fundedError = "Save failed"
        return
      }
      root.refreshNow()
    }
  }

  Process {
    id: setApiKeyProcess
    running: false
    stdinEnabled: true
    onStarted: {
      write(root.pendingApiKey + "\n")
      root.pendingApiKey = ""
    }
    onExited: function(code) {
      root.pendingApiKey = ""
      if (code !== 0) {
        root.apiKeyError = "Could not save API key"
        return
      }
      root.refreshNow()
    }
  }

  // Countdowns and balances read this instead of Date.now() so the panel keeps
  // telling the truth while it sits open.
  property double nowMs: Date.now()

  // The bar dot answers for the whole list, and it answers for one thing: a
  // rolling window nearly spent. Red is a subscription's alarm — an allowance
  // you cannot buy back mid-window, where the only fix is to stop. A prepaid
  // wallet reading $0.00 is a different fact: the fix is a top-up, you can do
  // it any time, and a dot that stays red for days until you do is crying wolf
  // on a machine that has not spent a cent. So only windows light it.
  readonly property bool alarming: {
    for (var i = 0; i < providers.length; i++)
      if (providerAlarming(providers[i])) return true
    return false
  }

  function providerAlarming(p) {
    if (!p) return false
    var windows = limitWindows(p)
    for (var i = 0; i < windows.length; i++) {
      // Soft windows are drawn against the low end of a published range, not a
      // hard stop; lighting the bar for one would cry wolf.
      if (windows[i].soft) continue
      if (windows[i].percent >= 0.9) return true
    }
    return false
  }

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  function refreshNow() {
    usage.refreshAll(true)
  }

  // ---------------------------------------------------------- the harnesses
  //
  // Right-click answers a different question than the panel does: not "how much
  // is left?" but "where am I going out to spend it?". The list comes from the
  // plugin's own script, so it names only harnesses that are installed here and
  // a new one appears without an edit to this file.
  property bool launcherMode: false
  property var harnesses: []

  readonly property string harnessScript: localPath(Qt.resolvedUrl("bin/omarchy-agent-harnesses"))

  // The launcher is the panel in a second mode, not a second surface: the panel
  // already owns input, focus and Esc, which a nested popup inside a popup does
  // not reliably get.
  function openLauncher() {
    if (harnessScript === "") return
    launcherMode = true
    refreshHarnesses()
    if (!root.opened) root.open()
    harnessColumnFlick.contentY = 0
  }

  function refreshHarnesses() {
    if (harnessScript === "" || harnessListProcess.running) return
    harnessListProcess.running = true
  }

  function launchHarness(id) {
    if (harnessScript === "" || String(id || "") === "") return
    root.close()
    Quickshell.execDetached([harnessScript, "--launch", String(id)])
  }

  Process {
    id: harnessListProcess
    running: false
    command: [root.harnessScript, "--list"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text)
          root.harnesses = Array.isArray(parsed) ? parsed : []
        } catch (error) {
          root.harnesses = []
        }
      }
    }

    onExited: function(code) { if (code !== 0) root.harnesses = [] }
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
  function limitWindow(label, percent, resetAt, title, extra) {
    var window = {
      title: String(title || "") !== "" ? String(title) : windowTitle(label),
      percent: Number(percent),
      resetAt: String(resetAt || ""),
      soft: false,
      used: -1,
      capMin: 0,
      capMax: 0
    }
    // A measured-in-minutes window (Live Voice) carries its own figure and the
    // range it is drawn against; the panel shows them in the tooltip instead of
    // pretending the percentage is the whole story.
    if (extra && typeof extra === "object") {
      if (extra.soft === true) window.soft = true
      if (extra.used !== undefined && extra.used !== null) window.used = Number(extra.used)
      if (extra.capMin !== undefined && extra.capMin !== null) window.capMin = Number(extra.capMin)
      if (extra.capMax !== undefined && extra.capMax !== null) window.capMax = Number(extra.capMax)
    }
    return window
  }

  function limitWindows(p) {
    if (!p) return []
    var out = []
    var list = p.limits || []
    for (var i = 0; i < list.length; i++) {
      var entry = list[i] || {}
      var percent = Number(entry.percent)
      if (percent >= 0) out.push(limitWindow(entry.label, percent, entry.resetsAt, entry.title, entry))
    }
    return out
  }

  // The share the meter is drawn from, in words: "80%" alone leaves you guessing
  // which way it runs, and this is the number a hover is asking for.
  function percentPair(percent) {
    var used = Math.round(root.clamp(Number(percent) || 0, 0, 1) * 100)
    return used + "% used · " + Math.max(0, 100 - used) + "% left"
  }

  // A window whose figure is minutes rather than a percentage names both the
  // number and the published range, because "of 60" would misstate a 60–150 min
  // allowance.
  function windowValueText(w) {
    if (!w) return ""
    if (w.used >= 0 && w.capMin > 0) {
      var minutes = Math.round(w.used * 10) / 10
      var cap = Math.round(w.capMin) + (w.capMax > w.capMin ? "–" + Math.round(w.capMax) : "")
      return minutes + " of ~" + cap + " min"
    }
    return percentPair(w.percent)
  }

  function windowTooltipText(w) {
    if (!w) return ""
    var text = w.title + " · " + windowValueText(w)
    var remainingMs = resetMsFor(w)
    if (remainingMs > 0) text += " · resets in " + formatDuration(remainingMs)
    return text
  }

  // The bar icon answers "how much is left?" without opening the panel: one line
  // per subscription, naming its tightest real window, plus a measured voice
  // allowance when there is one. Soft windows never stand in for the tightest
  // window — their cap is a range, so their percentage is not a countdown.
  function tightestWindow(p) {
    var windows = limitWindows(p)
    var best = null
    for (var i = 0; i < windows.length; i++) {
      if (windows[i].soft) continue
      if (best === null || windows[i].percent > best.percent) best = windows[i]
    }
    return best
  }

  function voiceWindow(p) {
    var windows = limitWindows(p)
    for (var i = 0; i < windows.length; i++)
      if (windows[i].soft) return windows[i]
    return null
  }

  function barTooltipText() {
    var lines = []
    for (var i = 0; i < providers.length; i++) {
      var p = providers[i]
      var parts = [String(p.providerName || p.providerId || "")]
      var tight = tightestWindow(p)
      if (tight) parts.push(tight.title + " " + percentPair(tight.percent))
      var voice = voiceWindow(p)
      if (voice) parts.push(voice.title.toLowerCase() + " " + windowValueText(voice))
      if (parts.length > 1) lines.push(parts.join(" · "))
    }
    return lines.join("\n")
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
    var code = String(currency || "USD").toUpperCase()
    if (code === "CREDITS") {
      var whole = Math.round(Math.abs(amount)).toString()
      whole = whole.replace(/\B(?=(\d{3})+(?!\d))/g, ",")
      return (amount < 0 ? "-" : "") + whole + " credits"
    }
    // A negative ledger reads "-$0.01" rather than "$-0.01".
    return (amount < 0 ? "-" : "") + currencyPrefix(currency) + Math.abs(amount).toFixed(2)
  }

  // An estimate wears its caveat on the figure: "~" is the universal "about",
  // and it survives an elided line where a trailing word does not.
  function balanceLabel(providerId, api) {
    if (api) return "API Balance"
    var id = String(providerId || "")
    if (id === "opencode-go") return "Zen Balance"
    if (id === "openai") return "Credits"
    return "Balance"
  }

  function balanceText(b) {
    if (!b) return ""
    return (b.estimated ? "~" : "") + formatMoney(b.remaining, b.currency)
  }

  // The line under the name is the plan level, and only a plan level: "Plus",
  // "Go", "Pro". How an account is billed ("Prepaid", "Subscription") is what
  // the panel groups rows by, so repeating it under the name says nothing.
  function subText(p) {
    if (!p) return ""
    if (String(p.usageStatusText || "") !== "") return p.usageStatusText

    var tier = String(p.tierLabel || "")
    var generic = ["prepaid", "subscription"]
    if (generic.indexOf(tier.toLowerCase()) !== -1) tier = ""
    if (tier !== "") tier = tier.charAt(0).toUpperCase() + tier.slice(1)
    if (p.stale) tier = tier === "" ? "Stale" : tier + " · stale"
    return tier
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
    // A fresh look at fresh numbers: start collapsed every time.
    expandedProviderId = ""
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
    function open(): void { root.launcherMode = false; root.open() }
    function close(): void { root.close() }
    function show(): void { root.launcherMode = false; root.open() }
    function hide(): void { root.close() }
    function toggle(): void { if (!root.opened) root.launcherMode = false; root.toggle() }
    function refresh(): string { root.refreshNow(); return "ok" }
    function next(): string { root.scrollToNextCard(); return "ok" }
    // Right-click has no IPC equivalent, so the launcher gets a name of its own.
    function launcher(): string { root.openLauncher(); return "ok" }
    // Launch one harness directly, for a keybinding or a script.
    function run(id: string): string { root.launchHarness(id); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󱚣"
    active: root.alarming
    // Hovering the icon is the fastest read of the whole list: the tightest
    // window per subscription, in both directions, without opening the panel.
    tooltipText: root.barTooltipText()
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.openLauncher()
      else if (buttonCode === Qt.MiddleButton) root.scrollToNextCard()
      else { root.launcherMode = false; root.toggle() }
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
    contentHeight: panel.fittedContentHeight(root.launcherMode ? harnessColumn.implicitHeight : column.implicitHeight, Style.space(640))

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
        visible: !root.launcherMode
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

          // The details for a mark-only button open under the whole row, so the
          // row keeps its even, icon-sized rhythm instead of one tile growing
          // taller than its neighbours.
          ProviderDetails {
            id: linkedDetails
            visible: root.expandedProviderId !== "" && root.linkedProviders.some(function(p) {
              return p.providerId === root.expandedProviderId
            })
            provider: root.linkedProviders.find(function(p) {
              return p.providerId === root.expandedProviderId
            }) || null
            width: parent.width
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
      // Right-click's list: the same surface and the same keys, one row per
      // harness this machine actually has.
      Flickable {
        id: harnessColumnFlick
        anchors.fill: parent
        visible: root.launcherMode
        contentWidth: width
        contentHeight: harnessColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        Column {
          id: harnessColumn
          width: harnessColumnFlick.width
          spacing: Style.space(2)

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: "Open a harness"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            topPadding: Style.space(2)
            bottomPadding: Style.space(4)
          }

          Repeater {
            model: root.harnesses

            delegate: Item {
              id: harnessRow
              required property var modelData
              width: parent.width
              height: Style.spacing.controlHeight

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: harnessHover.containsMouse ? root.alpha(root.foreground, 0.09) : "transparent"

                Behavior on color { ColorAnimation { duration: 120 } }
              }

              Text {
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: harnessRow.modelData ? String(harnessRow.modelData.label || "") : ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: harnessRow.modelData ? String(harnessRow.modelData.detail || "") : ""
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                id: harnessHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.launchHarness(harnessRow.modelData ? harnessRow.modelData.id : "")
              }
            }
          }
        }
      }
    }
  }

  // What sits behind a card once it is expanded. It is the same block for a
  // full row and for a mark-only button, because what you can configure has
  // nothing to do with whether the figure happens to be readable.
  component ProviderDetails: Column {
    id: providerDetails
    property var provider: null

    readonly property string url: root.billingUrl(provider ? provider.providerId : "")
    readonly property string apiUrl: provider && provider.providerId === "openai"
      ? root.billingUrl("openai-api") : ""
    readonly property string name: provider ? String(provider.providerName || provider.providerId) : ""
    readonly property bool funded: root.needsFundedAmount(provider)
    readonly property bool apiKey: provider && root.apiKeyProviderIds.indexOf(provider.providerId) !== -1
    readonly property string configPath: root.providerConfigPath(provider ? provider.providerId : "")
    readonly property var resets: provider && provider.resets ? provider.resets : null
    readonly property string balanceStatusText: provider ? String(provider.balanceStatusText || "") : ""

    // Fill from whatever is already recorded each time the card opens, and
    // leave it alone while it is open so a refresh cannot wipe out typing.
    onVisibleChanged: if (visible) fundedField.text = currentFunded()

    function currentFunded() {
      var b = provider ? provider.balance : null
      return b && b.funded > 0 ? Number(b.funded).toFixed(2) : ""
    }

    function commitFunded(text) {
      var amount = Number(String(text || "").trim())
      // A negative reading is valid: an overdrawn prepaid account is a thing.
      if (!isFinite(amount)) return
      root.saveFundedAmount(provider ? provider.providerId : "", amount.toFixed(2))
    }

    function commitApiKey(text) {
      var value = String(text || "").trim()
      if (value !== "") root.saveApiKey(provider ? provider.providerId : "", value)
    }

    width: parent ? parent.width : implicitWidth
    topPadding: Style.space(4)
    spacing: Style.space(4)

    // The link comes first: it is the thing you reach for most, and it is the
    // only one every provider has.
    Item {
      visible: providerDetails.url !== ""
      width: parent.width
      implicitHeight: linkLabel.implicitHeight + Style.space(12)

      Rectangle {
        anchors.fill: parent
        radius: Style.cornerRadius
        color: root.alpha(root.foreground, linkHover.containsMouse ? 0.10 : 0.05)

        Behavior on color { ColorAnimation { duration: 120 } }
      }

      Text {
        id: linkLabel
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        text: providerDetails.provider && providerDetails.provider.providerId === "openai"
          ? "Open ChatGPT / Codex usage"
          : "Open " + providerDetails.name + "'s billing page"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      MouseArea {
        id: linkHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.openBilling(providerDetails.provider)
      }
    }

    // OpenAI uses two separate account surfaces: keep the API billing link
    // beside the ChatGPT/Codex usage link rather than merging their URLs.
    Item {
      visible: providerDetails.apiUrl !== ""
      width: parent.width
      implicitHeight: apiLinkLabel.implicitHeight + Style.space(12)

      Rectangle {
        anchors.fill: parent
        radius: Style.cornerRadius
        color: root.alpha(root.foreground, apiLinkHover.containsMouse ? 0.10 : 0.05)

        Behavior on color { ColorAnimation { duration: 120 } }
      }

      Text {
        id: apiLinkLabel
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        text: "Open OpenAI API billing"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      MouseArea {
        id: apiLinkHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.openUrl(providerDetails.apiUrl)
      }
    }

    // Rate-limit resets: a way to get more allowance, and one that expires, so
    // the deadline is stated rather than just the count.
    Text {
      textFormat: Text.PlainText
      visible: providerDetails.resets !== null
      width: parent.width
      text: {
        var r = providerDetails.resets
        if (!r) return ""
        var count = Number(r.available || 0)
        var text = count + (count === 1 ? " reset available" : " resets available")
        var expires = String(r.nextExpiresAt || "")
        if (expires !== "") text += " · next expires " + root.shortDate(expires)
        return text
      }
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    // A balance the card could not read this time. It sits in the details
    // rather than under the name, because a stale console session is a note
    // about one figure, not a broken subscription.
    Text {
      textFormat: Text.PlainText
      visible: String(providerDetails.balanceStatusText || "") !== ""
      width: parent.width
      text: providerDetails.balanceStatusText
      color: root.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    // The estimate's missing half. This is a payment record, not a balance: it
    // is the total you have put in, which is what makes `funded − spent`
    // answerable for a provider whose ledger is dashboard-only.
    Item {
      visible: providerDetails.funded
      width: parent.width
      implicitHeight: Math.max(fundedLabel.implicitHeight, fundedField.implicitHeight) + Style.space(8)

      Text {
        id: fundedLabel
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.fundedError !== "" ? root.fundedError : "Balance"
        color: root.fundedError !== "" ? root.urgent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        width: Style.space(64)
        elide: Text.ElideRight
      }

      TextField {
        id: fundedField
        anchors.left: fundedLabel.right
        anchors.leftMargin: Style.space(6)
        anchors.right: fundedSave.left
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        placeholderText: "balance you can see, e.g. 3.77"
        foreground: root.foreground
        font.family: root.fontFamily
        verticalPadding: Style.space(4)
        // Standard notation in the C locale: money is written "20.00", not
        // "20,00", whatever the desktop's locale says.
        validator: DoubleValidator {
          // A balance can legitimately read below zero: that is what overdrawn
          // looks like, and it is worth being able to type it in.
          bottom: -1000000
          top: 1000000
          decimals: 2
          locale: "C"
          notation: DoubleValidator.StandardNotation
        }
        onAccepted: providerDetails.commitFunded(text)
      }

      Button {
        id: fundedSave
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "Save"
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        verticalPadding: Style.space(4)
        onClicked: providerDetails.commitFunded(fundedField.text)
      }
    }

    Item {
      visible: providerDetails.apiKey
      width: parent.width
      implicitHeight: Math.max(apiKeyLabel.implicitHeight, apiKeyField.implicitHeight) + Style.space(8)

      Text {
        id: apiKeyLabel
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.apiKeyError !== "" ? root.apiKeyError : "Go API key"
        color: root.apiKeyError !== "" ? root.urgent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        width: Style.space(84)
        elide: Text.ElideRight
      }

      TextField {
        id: apiKeyField
        anchors.left: apiKeyLabel.right
        anchors.leftMargin: Style.space(6)
        anchors.right: apiKeySave.left
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        placeholderText: "paste a replacement key"
        echoMode: TextInput.Password
        foreground: root.foreground
        font.family: root.fontFamily
        verticalPadding: Style.space(4)
        onAccepted: providerDetails.commitApiKey(text)
      }

      Button {
        id: apiKeySave
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "Save"
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        verticalPadding: Style.space(4)
        onClicked: providerDetails.commitApiKey(apiKeyField.text)
      }
    }

    Text {
      textFormat: Text.PlainText
      visible: providerDetails.apiKey
      width: parent.width
      text: "Saved to ~/.config/omarchy/agents/opencode-go.json; key hidden; OPENCODE_GO_API_KEY overrides it"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    Button {
      visible: providerDetails.apiKey
      width: parent.width
      text: "Edit key file"
      foreground: root.foreground
      fontFamily: root.fontFamily
      fontSize: Style.font.bodySmall
      verticalPadding: Style.space(4)
      onClicked: root.editApiKeyFile()
    }

    // Reordering, inside the group. Two buttons rather than a drag: dragging is
    // a lot of machinery for a list this short, and this needs no tutorial.
    Row {
      id: moveRow
      width: parent.width
      spacing: Style.spacing.md

      // The row decides from the same source the buttons do, rather than from
      // the buttons' own `visible`: a row that reads its children's visibility
      // evaluates before they do and stays hidden for good.
      readonly property bool canTop: root.canMoveToTop(providerDetails.provider)
      readonly property bool canBottom: root.canMoveToBottom(providerDetails.provider)
      // One button gets the full width; there is no empty half to leave behind.
      readonly property int visibleCount: (canTop ? 1 : 0) + (canBottom ? 1 : 0)
      readonly property real cellWidth: visibleCount > 0
        ? (width - spacing * (visibleCount - 1)) / visibleCount
        : 0

      visible: visibleCount > 0

      Button {
        id: topButton
        visible: moveRow.canTop
        width: visible ? moveRow.cellWidth : 0
        text: "Move to top"
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        verticalPadding: Style.space(4)
        onClicked: root.moveProvider(providerDetails.provider, true)
      }

      Button {
        id: bottomButton
        visible: moveRow.canBottom
        width: visible ? moveRow.cellWidth : 0
        text: "Move to bottom"
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        verticalPadding: Style.space(4)
        onClicked: root.moveProvider(providerDetails.provider, false)
      }
    }

    Row {
      id: visibilityRow
      visible: root.canHide(providerDetails.provider) || root.canShow(providerDetails.provider)
      width: parent.width
      spacing: Style.spacing.md

      Button {
        id: hideButton
        visible: root.canHide(providerDetails.provider)
        width: visible ? visibilityRow.width : 0
        text: "Hide"
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        verticalPadding: Style.space(4)
        onClicked: root.setHidden(providerDetails.provider, true)
      }

      Button {
        id: showButton
        visible: root.canShow(providerDetails.provider)
        width: visible ? visibilityRow.width : 0
        text: "Show"
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        verticalPadding: Style.space(4)
        onClicked: root.setHidden(providerDetails.provider, false)
      }
    }

    Text {
      textFormat: Text.PlainText
      visible: text !== ""
      width: parent.width
      text: root.orderError
      color: root.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // A reset expiry is read at a glance, so: short, and in the reader's own time.
  function shortDate(iso) {
    var ms = new Date(String(iso || "")).getTime()
    if (!isFinite(ms)) return ""
    var d = new Date(ms)
    var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    var hour = d.getHours()
    var suffix = hour >= 12 ? "PM" : "AM"
    var h12 = hour % 12
    if (h12 === 0) h12 = 12
    return months[d.getMonth()] + " " + d.getDate() + ", " + h12 + ":"
      + String(d.getMinutes()).padStart(2, "0") + " " + suffix
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
    readonly property var apiBalance: provider ? (provider.apiBalance || null) : null
    readonly property bool hasStatus: String(provider ? provider.usageStatusText : "") !== ""

    // The fullest window is the one that will stop the next prompt, so it keeps
    // full contrast while the rest recede.
    readonly property real bindingPercent: {
      var best = -1
      for (var i = 0; i < limits.length; i++) best = Math.max(best, limits[i].percent)
      return best
    }

    // The active block on the right. A row only exists when it has a figure, so
    // this is either the balance or the window list; a status line takes the
    // name column instead and leaves this empty.
    // A card can legitimately have both a rolling window and a credit balance
    // (a ChatGPT plan with usage credits). The windows are the thing that stops
    // you, so they keep the trailing space and the credit moves up under the
    // name, where it still reads as a second, smaller fact.
    readonly property var trailingBlock: hasStatus
      ? null
      : metricColumn

    width: parent ? parent.width : implicitWidth
    implicitHeight: summary.implicitHeight + (details.visible ? details.height + Style.spacing.md : 0)

    readonly property bool expanded: root.expandedProviderId === (provider ? provider.providerId : "")
    readonly property bool hovered: rowHover.containsMouse

    // Which window line the pointer is on. The card itself is one big click
    // target, so a line never receives hover on its own; the pointer position is
    // resolved against the drawn lines instead.
    readonly property int hoveredLimitIndex: {
      if (!hovered || !windowColumn || limits.length === 0) return -1
      var y = rowHover.mouseY
      var origin = windowColumn.mapToItem(providerRow, 0, 0).y
      for (var i = 0; i < windowColumn.children.length; i++) {
        var line = windowColumn.children[i]
        if (!line || line.height <= 0 || line.visible === false) continue
        if (y >= origin + line.y && y <= origin + line.y + line.height) return i
      }
      return -1
    }

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      // An open card stays lit so it is obvious which one you are looking at.
      color: root.alpha(root.foreground, (providerRow.hovered || providerRow.expanded) ? 0.09 : 0.04)

      Behavior on color { ColorAnimation { duration: 120 } }
    }

    Item {
      id: summary
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      implicitHeight: Math.max(Style.font.display, labels.implicitHeight, trailing.height) + Style.spacing.xl

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
          // Nothing to say means nothing on screen: a plan-less account gives
          // the name the whole left column instead of a stray empty line.
          visible: text !== ""
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
          id: metricColumn
          visible: !providerRow.hasStatus && (!!providerRow.balance || !!providerRow.apiBalance || providerRow.limits.length > 0)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(150)
          spacing: Style.space(3)

          Column {
            id: windowColumn
            visible: providerRow.limits.length > 0
            spacing: Style.space(2)

            Repeater {
              model: providerRow.limits

              LimitLine {
                required property var modelData
                window: modelData
                primary: modelData.percent >= providerRow.bindingPercent
              }
            }
          }

          Column {
            id: balanceBlock
            visible: !!providerRow.balance
            spacing: Style.space(2)

            Item {
              id: balanceRow
              width: metricColumn.width
              height: Math.max(balanceLabelText.implicitHeight, balanceValue.implicitHeight)

              Text {
                id: balanceLabelText
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.balanceLabel(providerRow.provider ? providerRow.provider.providerId : "", false)
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                id: balanceValue
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.balanceText(providerRow.balance)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                horizontalAlignment: Text.AlignRight
              }
            }
          }

          Column {
            id: apiBalanceBlock
            visible: !!providerRow.apiBalance
            spacing: Style.space(2)

            Item {
              id: apiBalanceRow
              width: metricColumn.width
              height: Math.max(apiBalanceLabelText.implicitHeight, apiBalanceValue.implicitHeight)

              Text {
                id: apiBalanceLabelText
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.balanceLabel("", true)
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                id: apiBalanceValue
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.balanceText(providerRow.apiBalance)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                horizontalAlignment: Text.AlignRight
              }
            }
          }
        }
      }

      // Clicking the card opens it rather than leaving for the browser: the page
      // it would have opened is the first thing inside.
      MouseArea {
        id: rowHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggleExpanded(providerRow.provider ? providerRow.provider.providerId : "")
      }

      // The bar is a picture of one number; the hover says which number, in both
      // directions, and when the window comes back.
      PanelToolTip {
        visible: providerRow.hoveredLimitIndex >= 0
        text: {
          var index = providerRow.hoveredLimitIndex
          if (index < 0 || index >= providerRow.limits.length) return ""
          return root.windowTooltipText(providerRow.limits[index])
        }
        fontFamily: root.fontFamily
      }
  }

  ProviderDetails {
    id: details
    visible: providerRow.expanded
    provider: providerRow.provider
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: summary.bottom
    anchors.leftMargin: Style.spacing.xl
    anchors.rightMargin: Style.spacing.xl
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
    readonly property bool expanded: root.expandedProviderId === (provider ? provider.providerId : "")

    implicitHeight: Style.font.display + Style.spacing.xl

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      // A button whose details are open stays lit, so the block underneath is
      // clearly attached to it.
      color: root.alpha(root.foreground, (linkedButton.hovered || linkedButton.expanded) ? 0.09 : 0.04)

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
      onClicked: root.toggleExpanded(linkedButton.provider ? linkedButton.provider.providerId : "")
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
    // Wide enough for the longest window name the panel draws ("Voice"), so a
    // spelled-out label never runs into its own bar.
    readonly property real labelWidth: Style.space(32)
    readonly property real resetWidth: Style.space(52)
    readonly property real alarming: window ? (!window.soft && window.percent >= 0.9) : false

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
