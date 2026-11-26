import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Every subscription on one screen. A subscription tells you how much of its
// allowance is left and when it comes back; a pay-per-token account tells you
// what is still on the meter. That is the balance sheet, and it is what a left
// click opens. What has already gone — the ledgers, the counts, and the
// harnesses the next lot goes out from — is the other half of the same records,
// and it waits behind a right click instead of padding the view you came for.
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

  // ------------------------------------------------------------------- tokens

  // What the collectors' per-model ledgers add up to. modelUsage carries no
  // dates — the only dated field beside it is a week of message counts — so the
  // one honest total in these records is a lifetime one, and the block below
  // labels it that way rather than implying a window the data cannot measure.
  function tokenCount(value) {
    var n = Number(value)
    return isFinite(n) && n > 0 ? n : 0
  }

  // Cached reads are kept apart from the rest: on a long agent session the cache
  // column dwarfs every other one, and folded into the total it would make the
  // figure unreadable and any comparison between providers meaningless.
  function providerTokens(p) {
    var usage = (p && p.modelUsage) || ({})
    var total = 0
    var cached = 0
    for (var model in usage) {
      var bucket = usage[model] || ({})
      total += tokenCount(bucket.inputTokens) + tokenCount(bucket.outputTokens)
      cached += tokenCount(bucket.cacheReadInputTokens) + tokenCount(bucket.cacheCreationInputTokens)
    }
    return { total: total, cached: cached }
  }

  // One entry per provider that has a ledger, plus the sum across all of them.
  // A provider whose collector records no modelUsage contributes nothing and
  // gets no row — a zero there would read as "used none" rather than "not
  // measured" — and with no ledgers at all the whole block stays hidden. This
  // is a binding on the loaded records, not a per-render scan: it recomputes
  // when the records change and not once per frame.
  readonly property var tokenLedger: {
    var rows = []
    var total = 0
    var cached = 0
    for (var i = 0; i < providers.length; i++) {
      var sums = providerTokens(providers[i])
      if (sums.total + sums.cached <= 0)
        continue
      rows.push({ name: providers[i].providerName, total: sums.total, cached: sums.cached })
      total += sums.total
      cached += sums.cached
    }
    return { rows: rows, total: total, cached: cached }
  }

  // A compact figure is what makes two providers comparable at a glance.
  function formatTokens(value) {
    var n = tokenCount(value)
    if (n >= 1e9)
      return scaledTokens(n / 1e9) + "B"
    if (n >= 1e6)
      return scaledTokens(n / 1e6) + "M"
    if (n >= 1e3)
      return scaledTokens(n / 1e3) + "K"
    return String(Math.round(n))
  }

  // One decimal while it carries information, none once the figure is big
  // enough that the decimal is only clutter: "1.4M" but "68M".
  function scaledTokens(scaled) {
    return scaled >= 100 ? String(Math.round(scaled)) : scaled.toFixed(1).replace(/\.0$/, "")
  }

  // The figure as it is written everywhere: the total, with cached reads off to
  // the side. One function rather than one per block, because the panel total
  // and an open card's own line are the same sentence about different records,
  // and two copies of it would eventually disagree.
  function tokenFigureText(total, cached) {
    var text = formatTokens(total)
    if (tokenCount(cached) > 0)
      text += "  +" + formatTokens(cached) + " cache"
    return text
  }

  // The same ledger, read one provider at a time for the card that is open. No
  // second sum: this is `providerTokens` on a single record, laid out as the
  // lines the details draw. A figure the record does not hold gets no line at
  // all — a zero there would read as "used none" when the truth is "not
  // measured" — so an agent that reports only a balance opens to just its link,
  // and one that reports only counts opens to those alone.
  function providerUsageRows(p) {
    var rows = []
    if (!p) return rows
    var sums = providerTokens(p)
    if (sums.total + sums.cached > 0)
      rows.push({ label: "Tokens", figure: tokenFigureText(sums.total, sums.cached) })
    // Counts run beside the ledger. A collector that reads only tokens says so
    // with hasPromptStats, and its prompt count would be a false zero.
    var prompts = p.hasPromptStats === false ? 0 : tokenCount(p.totalPrompts)
    if (prompts > 0)
      rows.push({ label: "Prompts", figure: countText(prompts) })
    if (tokenCount(p.totalSessions) > 0)
      rows.push({ label: "Sessions", figure: countText(p.totalSessions) })
    if (tokenCount(p.activeDays) > 0)
      rows.push({ label: "Active days", figure: countText(p.activeDays) })
    return rows
  }

  // Counts stay whole: "12,431 prompts" is the number, where "12.4K" is only
  // its size. Grouped by threes in the C convention, matching the money fields
  // rather than whatever the desktop's locale would do to them.
  function countText(value) {
    var digits = String(Math.round(tokenCount(value)))
    var out = ""
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 === 0) out += ","
      out += digits.charAt(i)
    }
    return out
  }

  // Prompts and sessions, added up the way the ledger is: across every provider
  // at once, because "how much has gone" is the one question a per-card view
  // cannot answer. A collector that reads only tokens says so with
  // hasPromptStats, and folding its zero in would read as "prompted never".
  readonly property var usageCounts: {
    var prompts = 0
    var sessions = 0
    for (var i = 0; i < providers.length; i++) {
      var p = providers[i]
      if (!p) continue
      if (p.hasPromptStats !== false) prompts += tokenCount(p.totalPrompts)
      sessions += tokenCount(p.totalSessions)
    }
    return { prompts: prompts, sessions: sessions }
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

  // ------------------------------------------------- provider-reported totals

  // The figure each provider's own console reports, which is the only place a
  // real lifetime number exists: the local records only know what this machine
  // ran. Every row carries the window its provider actually covers, because the
  // three differ — DeepSeek keeps the whole account, OpenAI keeps 12 months, and
  // the OpenCode console keeps one billing period.
  readonly property string lifetimePath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omarchy/agents/lifetime.json"
  property var lifetimeProviders: []
  property string lifetimeFetchedAt: ""
  property string lifetimeApplied: ""

  FileView {
    id: lifetimeFile
    path: root.lifetimePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyLifetime(text())
    // A read that fails once must not blank a block that is still true: the
    // paragraphs already on screen are the last thing this file said, and the
    // timestamp under them says how old they are.
    onLoadFailed: {}
  }

  function applyLifetime(content) {
    // Rebuilding the rows replaces the array, and a replaced array tears down
    // and recreates every Repeater delegate — a visible flash on a row that did
    // not change. The file only matters when its text does.
    var loaded = String(content || "")
    if (loaded === lifetimeApplied) return
    lifetimeApplied = loaded
    var parsed = null
    try { parsed = JSON.parse(String(content || "")) } catch (e) { parsed = null }
    var entries = parsed && parsed.providers ? parsed.providers : {}
    var rows = []
    var order = ["deepseek", "openai", "opencode-go"]
    for (var i = 0; i < order.length; i++) {
      var entry = entries[order[i]]
      if (!entry) continue
      var tokens = tokenCount(entry.totalTokens)
      var requests = tokenCount(entry.requests)
      var spent = Number(entry.spent || 0)
      var figure = ""
      if (tokens > 0) figure += formatTokens(tokens) + " tok"
      if (requests > 0) figure += (figure === "" ? "" : " · ") + countText(requests) + " req"
      if (spent > 0) figure += (figure === "" ? "" : " · ") + currencyPrefix(entry.spentCurrency) + spent.toFixed(2)
      rows.push({
        providerId: order[i],
        name: entryScopeName(order[i]),
        window: lifetimeWindowText(entry),
        figure: figure
      })
    }
    // Money that is not usage on the same card: what the plan has been paid.
    // Kept apart from the period's tokens so neither reads as the other.
    var paid = entries["opencode-go"] && Number(entries["opencode-go"].paidLifetime || 0)
    if (paid > 0)
      rows.push({ providerId: "opencode-go-paid", name: "OpenCode Go · paid to date", window: "", figure: currencyPrefix(entries["opencode-go"].paidCurrency) + paid.toFixed(2) })
    root.lifetimeProviders = rows
    root.lifetimeFetchedAt = String(parsed && parsed.fetchedAt ? parsed.fetchedAt : "")
  }

  function entryScopeName(providerId) {
    if (providerId === "deepseek") return "DeepSeek · lifetime"
    if (providerId === "openai") return "OpenAI · last 12 months"
    if (providerId === "opencode-go") return "OpenCode Go · this period"
    return providerId
  }

  function lifetimeWindowText(entry) {
    var since = String(entry && entry.since ? entry.since : "")
    var through = String(entry && entry.through ? entry.through : "")
    if (since !== "" && through !== "") return since + " → " + through
    if (since !== "") return "since " + since
    return ""
  }

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

  // The one write behind a drag: the arrangement the collector is asked to
  // remember. Both the reorder and the hide paths go through it.
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

  // ------------------------------------------------------------- dragging
  //
  // The hand's version of the two writes above: a card dragged down into the
  // row of marks collapses to a mark, a mark dragged up out of that row becomes
  // a card again, and a card dropped in the seam between two cards lands there.
  // Nothing is written until the pointer comes up, because committing mid-drag
  // re-sorts the model under the delegate that is holding the pointer and the
  // drag dies with it.
  property string dragProviderId: ""
  // Which way the drag is going. A card can only be dragged down and a mark only
  // up, so the two gestures never disagree about what a drop means.
  property bool dragFromCard: false
  readonly property bool dragging: dragProviderId !== ""

  // The live drop target. Worked out while the pointer moves, then read by the
  // indicators drawn over the list.
  property int dropSlot: -1
  property bool dropOnLinkedRow: false
  property bool dropOnCards: false
  // Marks that are marks because there is no number to draw have no card to go
  // back to, so pulling one out of the row opens the block a click opens. The
  // gesture means "more of this one" either way; only the destination differs,
  // and the alternative is a drag that silently does nothing for exactly the
  // providers that are always marks.
  property bool dropOpensDetails: false
  property real dropStripeY: 0
  property real linkedZoneY: 0
  property real linkedZoneHeight: 0
  property real cardZoneY: 0
  property real cardZoneHeight: 0

  // The cards and the marks meet on an edge that nothing draws, so a mark
  // released a few pixels short of it used to commit nothing at all — the seam
  // was a pixel the hand had to hit. Slack on the outward side gives the gesture
  // a band to land in. Scaled like every other gap here rather than fixed in
  // pixels.
  readonly property real dragSeamSlack: Style.space(8)

  // TEMPORARY DIAGNOSTIC — counts the calls one drag makes, so the journal reads
  // as a path instead of a set of states. Remove with the other DRAGDBG lines.
  property int dragTicks: 0

  function isDragging(p) { return !!p && dragProviderId === String(p.providerId) }

  function beginDrag(p, fromCard) {
    dragTicks = 0
    // TEMPORARY DIAGNOSTIC — remove with the other DRAGDBG lines. The capability
    // fields are here because the answer to "why did this one never move" is
    // usually that the provider has nothing to put in a card.
    console.warn("DRAGDBG beginDrag provider=" + (p ? p.providerId : "null")
                 + " fromCard=" + fromCard + " collectorPath='" + root.collectorPath + "'"
                 + " hidden=" + (p ? isHidden(p) : "null")
                 + " hasFigure=" + (p ? hasFigure(p) : "null")
                 + " canShow=" + (p ? canShow(p) : "null")
                 + " canHide=" + (p ? canHide(p) : "null"))
    if (!p || root.collectorPath === "") return
    dragProviderId = String(p.providerId)
    dragFromCard = fromCard
  }

  // Which seam the pointer is over: before the first card whose middle it has
  // not passed yet, or after the last one.
  function dropSlotAt(y) {
    var cards = cardItems()
    for (var i = 0; i < cards.length; i++)
      if (y < cards[i].y + cards[i].height / 2) return i
    return cards.length
  }

  // The seam draws on the leading edge of the card at that slot, or under the
  // last card when the slot is the end of the list.
  function slotY(slot) {
    var cards = cardItems()
    if (cards.length === 0) return 0
    if (slot >= cards.length) return cards[cards.length - 1].y + cards[cards.length - 1].height
    return cards[Math.max(0, slot)].y
  }

  function updateDrag(scenePosition) {
    if (!root.dragging) return
    dragTicks++
    var p = providerById(dragProviderId)
    // Measured against the drawn cards rather than against the Flickable: the
    // list can still move mid-drag, and a card that has scrolled is a different
    // card under the same pointer.
    var y = column.mapFromItem(null, scenePosition.x, scenePosition.y).y
    // Where the marks begin. Everything from there down is the collapse zone,
    // which is a far easier target than the row's own height.
    var marksTop = linkedRow.visible ? linkedRow.y : -1
    // The outward edge, opened out by the slack: a mark released just short of
    // the row's top is asking for the cards, and it used to get nothing at all
    // because the seam was a pixel the hand had to hit. The card's own edge
    // stays exact — a card released either side of it always commits something
    // (the row, or the seam after the last card), so it has nothing to forgive.
    var outOfRow = marksTop < 0 ? -1 : marksTop + dragSeamSlack

    dropSlot = -1
    dropOnLinkedRow = false
    dropOnCards = false
    dropOpensDetails = false

    if (dragFromCard) {
      if (p && canHide(p) && marksTop >= 0 && y >= marksTop)
        dropOnLinkedRow = true
      else
        dropSlot = dropSlotAt(y)
    } else if (p && marksTop >= 0 && y <= outOfRow) {
      // Out of the row is the whole gesture. Where it lands depends on what the
      // provider has to show: a hidden card comes back, and one that only ever
      // was a mark opens the block underneath instead.
      if (canShow(p))
        dropOnCards = true
      else if (!hasFigure(p))
        dropOpensDetails = true
    }

    if (dropSlot >= 0)
      dropStripeY = dragOverlay.mapFromItem(column, 0, slotY(dropSlot)).y
    if (marksTop >= 0) {
      linkedZoneY = dragOverlay.mapFromItem(column, 0, marksTop).y
      linkedZoneHeight = linkedRow.height
    }

    var cards = cardItems()
    if (cards.length > 0) {
      var last = cards[cards.length - 1]
      cardZoneY = dragOverlay.mapFromItem(column, 0, cards[0].y).y
      cardZoneHeight = dragOverlay.mapFromItem(column, 0, last.y + last.height).y - cardZoneY
    }

    // TEMPORARY DIAGNOSTIC — every call, not only the calls that change the
    // answer, so the journal holds the whole path the pointer took. The
    // capability fields are the point: a mark with no figure never changed the
    // answer, so it logged nothing at all and looked like a dead handler.
    // Remove with the other DRAGDBG lines.
    console.warn("DRAGDBG update #" + dragTicks
                 + " provider=" + dragProviderId + " fromCard=" + dragFromCard
                 + " sceneY=" + Math.round(scenePosition.y)
                 + " y=" + Math.round(y)
                 + " marksTop=" + Math.round(marksTop)
                 + " slack=" + Math.round(dragSeamSlack)
                 + " slot=" + dropSlot
                 + " ontoCards=" + dropOnCards + " ontoMarks=" + dropOnLinkedRow
                 + " ontoDetails=" + dropOpensDetails
                 + " cardZone=" + Math.round(cardZoneY) + "/" + Math.round(cardZoneHeight)
                 + " marksZone=" + Math.round(linkedZoneY) + "/" + Math.round(linkedZoneHeight)
                 + " cards=" + cards.length
                 + " hidden=" + (p ? isHidden(p) : "null")
                 + " hasFigure=" + (p ? hasFigure(p) : "null")
                 + " canShow=" + (p ? canShow(p) : "null")
                 + " canHide=" + (p ? canHide(p) : "null"))
  }

  // The release is the only thing that writes. One drop means one call.
  function endDrag() {
    var p = providerById(dragProviderId)
    var slot = dropSlot
    var ontoMarks = dropOnLinkedRow
    var ontoCards = dropOnCards
    var ontoDetails = dropOpensDetails
    var dropped = dragProviderId
    var ticks = dragTicks
    resetDrag()
    // TEMPORARY DIAGNOSTIC — the answer and the write it turns into, so a release
    // that commits nothing says which of the two was empty. Remove with the
    // other DRAGDBG lines.
    var action = "none"
    if (!p) action = "noProvider"
    else if (ontoMarks) action = "hide"
    else if (ontoCards) action = "show"
    else if (ontoDetails) action = "details"
    else if (slot >= 0) action = "reorder"
    console.warn("DRAGDBG endDrag provider=" + dropped + " ticks=" + ticks
                 + " slot=" + slot + " ontoMarks=" + ontoMarks + " ontoCards=" + ontoCards
                 + " ontoDetails=" + ontoDetails + " action=" + action)
    if (!p) return
    if (ontoMarks) setHidden(p, true)
    else if (ontoCards) setHidden(p, false)
    else if (ontoDetails) expandedProviderId = String(p.providerId)
    else if (slot >= 0) reorderProvider(p, slot)
  }

  // A drag Qt takes away — Esc, the panel closing, a second pointer — writes
  // nothing at all.
  function resetDrag() {
    dragProviderId = ""
    dragFromCard = false
    dropSlot = -1
    dropOnLinkedRow = false
    dropOnCards = false
    dropOpensDetails = false
    dragTicks = 0
  }

  // Landing a card in a seam. The slot counts positions in the list as it was
  // drawn, so pulling the card out of that list first moves every seam below it
  // up by one. What is left is then held to the group, for the same reason the
  // move functions were: the group is the rule, and a subscription can never be
  // stored below a prepaid account.
  function reorderProvider(p, slot) {
    if (!p || root.collectorPath === "") return

    var drawn = []
    for (var i = 0; i < root.meteredProviders.length; i++)
      drawn.push(String(root.meteredProviders[i].providerId))
    var from = drawn.indexOf(String(p.providerId))
    if (from === -1) return
    drawn.splice(from, 1)

    var at = slot > from ? slot - 1 : slot
    var rank = usage.providerRank(p)
    var lo = drawn.length
    var hi = drawn.length
    for (var j = 0; j < drawn.length; j++) {
      var sibling = root.providerById(drawn[j])
      if (!sibling || usage.providerRank(sibling) !== rank) continue
      if (lo === drawn.length) lo = j
      hi = j + 1
    }
    // Nothing of its own group left to slide past: the rank decides this one's
    // place, and a write for it would only be noise.
    if (lo === hi) return
    at = root.clamp(at, lo, hi)

    // The seam is expressed against the card on its far side, so the write only
    // has to say "put this one before that one". Whatever else the collector
    // remembers about ids this list does not draw keeps its place around them.
    var anchorId = at < drawn.length ? drawn[at] : drawn[drawn.length - 1]

    var ids = []
    for (var k = 0; k < providers.length; k++) ids.push(providers[k].providerId)
    var remembered = root.knownProviderIds()
    for (var m = 0; m < remembered.length; m++)
      if (ids.indexOf(remembered[m]) === -1) ids.push(remembered[m])

    var current = ids.join(",")
    var removedAt = ids.indexOf(p.providerId)
    if (removedAt === -1) return
    ids.splice(removedAt, 1)

    var anchorAt = ids.indexOf(anchorId)
    if (anchorAt === -1) return
    ids.splice(at < drawn.length ? anchorAt : anchorAt + 1, 0, p.providerId)

    // A drop back where it started is not a change, and a write for it would
    // only make the card flicker.
    if (ids.join(",") === current) return

    orderError = ""
    setOrderProcess.command = [root.collectorPath, "--set-order", ids.join(",")]
    setOrderProcess.running = true
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

  // ---------------------------------------------------------- the usage view
  //
  // Two questions, two clicks. Left click is the balance sheet: what is left on
  // each meter. Right click is consumption: what has already gone, and where the
  // next lot goes out from. Both are this one panel in a different mode, not two
  // surfaces: the panel already owns input, focus and Esc, which a nested popup
  // inside a popup does not reliably get.
  property bool usageMode: false
  property var harnesses: []

  readonly property string harnessScript: localPath(Qt.resolvedUrl("bin/omarchy-agent-harnesses"))

  function openUsage() {
    usageMode = true
    if (harnessScript !== "") refreshHarnesses()
    if (!root.opened) root.open()
    if (panelFlick) panelFlick.contentY = 0
  }

  // The same gesture takes the view away again, so one click is the whole trip
  // out and back and nothing can be left showing that was not asked for.
  function toggleUsage() {
    if (root.opened && usageMode) root.close()
    else root.openUsage()
  }

  // Back to the balance sheet without closing anything: the left click and the
  // way out of the usage view are the same destination, so the two cannot
  // disagree about which view is showing.
  function showCapacity() {
    usageMode = false
    if (panelFlick) panelFlick.contentY = 0
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
    // OpenCode Go spends from the same wallet as Zen, and its console calls
    // what is left "available credit", so the row uses the console's own word.
    // The figure stays a dollar amount like every other money row; only the
    // label is provider-specific.
    if (id === "opencode-go") return "Credit"
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
    var base = assetBaseFor(p.providerId)
    var candidates = []
    if (colorLuminance(surfaceColor || Color.background) >= 0.5)
      candidates.push(Qt.resolvedUrl("assets/" + base + "-light.svg"))
    candidates.push(Qt.resolvedUrl("assets/" + base + ".svg"))
    return candidates
  }

  // opencode records real provider ids, and several of them are a variant of
  // the account whose mark ships (hermes-local runs on the Hermes account,
  // github-copilot on Copilot's). A literal id lookup misses, the Image errors,
  // and the failed load repeats on every repaint and every record refresh. Map
  // the id onto the family that owns the mark instead.
  function assetBaseFor(providerId) {
    var id = String(providerId || "")
    if (id.indexOf("hermes") === 0) return "hermes"
    if (id.indexOf("copilot") !== -1) return "github-copilot"
    return id
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
    // A panel that closed mid-drag never got its release, and a card left in
    // flight would take the list's scrolling away for good.
    resetDrag()
    if (panelFlick) panelFlick.contentY = 0
    usage.refreshLimits()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  } else {
    // No view outlives the close. The next open is the balance sheet unless the
    // click that opens it asks for the usage view, so the panel cannot come back
    // in a mode nobody chose.
    usageMode = false
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
    function open(): void { root.usageMode = false; root.open() }
    function close(): void { root.close() }
    function show(): void { root.usageMode = false; root.open() }
    function hide(): void { root.close() }
    function toggle(): void { if (!root.opened) root.usageMode = false; root.toggle() }
    function refresh(): string { root.refreshNow(); return "ok" }
    function next(): string { root.scrollToNextCard(); return "ok" }
    // Right-click has no IPC equivalent either way, so each view gets a name of
    // its own. `launcher` keeps its old name and now opens the usage view, which
    // is where the harness list lives, so a keybinding written for it still
    // lands on the list.
    function usage(): string { root.openUsage(); return "ok" }
    function launcher(): string { root.openUsage(); return "ok" }
    function capacity(): string { if (!root.opened) root.open(); root.showCapacity(); return "ok" }
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
    // Left is capacity, right is usage. Left stays the way in and the way out of
    // the other view — reaching the balance sheet is one click from either mode,
    // which is what keeps a mode from being a place to get stuck.
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.toggleUsage()
      else if (buttonCode === Qt.MiddleButton) root.scrollToNextCard()
      else if (root.opened && root.usageMode) root.showCapacity()
      else { root.usageMode = false; root.toggle() }
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
        // A card being dragged owns the pointer: letting the list scroll at the
        // same time would carry the seam out from under the card that is aiming
        // for it.
        interactive: !root.dragging && contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(8)

          // ---------- capacity ----------
          // Everything a left click opens, and nothing else: what is left on each
          // meter. The consumption side is the usage view further down, and the
          // two are never on screen together, so neither pads the other.

          PanelHero {
            width: parent.width
            visible: !root.usageMode
            title: "Agents"
            meta: root.meteredProviders.length + " metered · " + root.linkedProviders.length + " linked"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            visible: !root.usageMode && root.providers.length === 0
            width: parent.width
            topPadding: Style.space(24)
            text: "No AI coding subscriptions found.\nAgents show up here once you've used them."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          PanelSectionHeader {
            visible: !root.usageMode
            text: "Subscriptions"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: root.meteredProviders

            ProviderRow {
              provider: modelData
              // The card hides with the rest of the balance sheet; the row itself
              // is what a Column lays out, so the mode is decided here and not on
              // the Repeater.
              visible: !root.usageMode
            }
          }

          PanelSeparator {
            visible: !root.usageMode && root.linkedProviders.length > 0 && root.meteredProviders.length > 0
            foreground: root.foreground
          }

          // The providers whose numbers we cannot read: marks only, each one a
          // link to the page that has them.
          Row {
            id: linkedRow
            visible: !root.usageMode && root.linkedProviders.length > 0
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
            visible: !root.usageMode && root.expandedProviderId !== "" && root.linkedProviders.some(function(p) {
              return p.providerId === root.expandedProviderId
            })
            provider: root.linkedProviders.find(function(p) {
              return p.providerId === root.expandedProviderId
            }) || null
            width: parent.width
          }

          PanelSectionHeader {
            visible: !root.usageMode && root.syncFooter() !== ""
            text: "Status"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            textFormat: Text.PlainText
            visible: !root.usageMode && text !== ""
            width: parent.width
            topPadding: Style.space(4)
            text: root.syncFooter()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }

          // ---------- usage ----------
          // Right click's side of the panel: what has already gone rather than
          // what is left. The same ledgers the cards read, added up across every
          // provider, because a total is the one thing a per-card view cannot
          // tell you. These are lifetime figures, the only kind these records
          // hold, so the hero says "all time" rather than letting a reader assume
          // a month. Cached reads ride along on each line because they are real
          // spend, but off to the side: on opencode-go they are several times
          // everything else.
          Column {
            id: usageView
            width: parent.width
            visible: root.usageMode
            spacing: Style.space(8)

            PanelHero {
              width: parent.width
              title: "Usage"
              meta: "all time"
              foreground: root.foreground
              fontFamily: root.fontFamily
              // The way back, in words and in reach. A mode you leave by
              // guessing is a trap, and the hero reserves the space itself.
              trailingControl: capacityButton
            }

            // What each provider says about itself. This block sits above the
            // local ledger because it is the better number: the rows below can
            // only see sessions opencode recorded here, while this is the
            // account's own total, windows included in the labels.
            Column {
              id: reportedBlock
              width: parent.width
              visible: root.lifetimeProviders.length > 0
              spacing: Style.space(2)

              PanelSectionHeader {
                text: "Provider-reported"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Repeater {
                model: root.lifetimeProviders

                UsageLine {
                  required property var modelData
                  width: reportedBlock.width
                  label: modelData.name
                  figure: modelData.figure
                  note: modelData.window
                }
              }
            }

            Column {
              id: tokenBlock
              width: parent.width
              visible: root.tokenLedger.rows.length > 0
              spacing: Style.space(2)

              Repeater {
                model: root.tokenLedger.rows

                UsageLine {
                  required property var modelData
                  width: tokenBlock.width
                  label: modelData.name
                  figure: root.tokenFigureText(modelData.total, modelData.cached)
                }
              }

              // The grand total earns a rule and its own line: it is the one
              // figure here that is not a single provider. With a single ledger
              // it would only repeat the row above it, so it waits for a second.
              PanelSeparator {
                visible: root.tokenLedger.rows.length > 1
                foreground: root.foreground
              }

              UsageLine {
                visible: root.tokenLedger.rows.length > 1
                width: tokenBlock.width
                emphasized: true
                label: "All providers"
                figure: root.tokenFigureText(root.tokenLedger.total, root.tokenLedger.cached)
              }
            }

            // Prompts and sessions beside the tokens, in the same shape: counts
            // stay whole here, where "12.4K" would only be their size. These are
            // the sums, not per-provider figures — a card already opens to its
            // own counts — so the header says whose they are. A record that holds
            // neither figure gets no block at all.
            Column {
              id: countsBlock
              width: parent.width
              visible: root.usageCounts.prompts > 0 || root.usageCounts.sessions > 0
              spacing: Style.space(2)

              PanelSectionHeader {
                text: "Counts · all providers"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              UsageLine {
                visible: root.usageCounts.prompts > 0
                width: countsBlock.width
                label: "Prompts"
                figure: root.countText(root.usageCounts.prompts)
              }

              UsageLine {
                visible: root.usageCounts.sessions > 0
                width: countsBlock.width
                label: "Sessions"
                figure: root.countText(root.usageCounts.sessions)
              }
            }

            PanelSeparator {
              visible: root.harnesses.length > 0
              foreground: root.foreground
            }

            // Where the next lot goes out from. The list comes from the plugin's
            // own script, so it names only harnesses installed here and a new one
            // appears without an edit to this file.
            Column {
              id: harnessList
              width: parent.width
              visible: root.harnesses.length > 0
              spacing: Style.space(2)

              PanelSectionHeader {
                text: "Open a harness"
                foreground: root.foreground
                fontFamily: root.fontFamily
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

          // The usage view's way out, handed to the hero above as its trailing
          // control. Declared once, because a Component takes no room in a Column.
          Component {
            id: capacityButton

            Button {
              text: "Balances"
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.space(4)
              onClicked: root.showCapacity()
            }
          }
        }
      }

      // ---------- what a drag draws ----------
      // Above the list rather than inside it: an indicator that took part in the
      // layout would push the cards apart and change the answer it is drawing.
      // None of it takes the pointer — the handler that started the drag holds
      // that until the release.
      Item {
        id: dragOverlay
        anchors.fill: parent
        visible: root.dragging

        // Down into the marks: the row itself lights up, because the row is what
        // the card is asking to become. The band is padded by a gap so the
        // highlight covers the whole gesture rather than only the row's height.
        // A mark with nothing to meter lights the same band on the way out: the
        // block it opens appears under the row, so the row is where it lands.
        Rectangle {
          x: 0
          y: root.linkedZoneY - Style.spacing.md / 2
          width: dragOverlay.width
          height: root.linkedZoneHeight + Style.spacing.md
          visible: root.dropOnLinkedRow || root.dropOpensDetails
          radius: Style.cornerRadius
          color: root.alpha(Color.accent, 0.16)

          Behavior on color { ColorAnimation { duration: 120 } }
        }

        // Up out of the marks: the band the cards live in lights up, because the
        // mark is asking for a card somewhere in it.
        Rectangle {
          x: 0
          y: root.cardZoneY
          width: dragOverlay.width
          height: root.cardZoneHeight
          visible: root.dropOnCards
          radius: Style.cornerRadius
          color: root.alpha(Color.accent, 0.16)
        }

        // The seam the card would land in. A rule rather than a card-sized hole,
        // so the answer to "where would it go?" is one line to read.
        Rectangle {
          x: 0
          y: root.dropStripeY - height / 2
          width: dragOverlay.width
          height: Style.space(2)
          visible: root.dropSlot >= 0
          radius: height / 2
          color: Color.accent
        }
      }
    }
  }

  // One labelled figure: the shape the panel's token block and an open card's
  // usage section both draw. Anchored rather than a Row for the same reason the
  // window lines are — the label elides against the figure, and the two share a
  // baseline without a positioner having to decide it.
  component UsageLine: Item {
    id: usageLine
    property string label: ""
    property string figure: ""
    // The one line that is a sum of the others, wherever it is drawn.
    property bool emphasized: false
    // The window behind a figure, when the figure does not cover everything.
    // It is a second line rather than part of the label so the number stays
    // readable and the caveat stays attached to it.
    property string note: ""

    width: parent ? parent.width : implicitWidth
    implicitHeight: usageRow.height + (usageNote.visible ? usageNote.implicitHeight + Style.space(1) : 0)
    height: implicitHeight

    Item {
      id: usageRow
      width: parent.width
      height: Math.max(usageLabel.implicitHeight, usageFigure.implicitHeight)

      Text {
        id: usageLabel
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: usageRow.width - usageFigure.width - Style.spacing.md
        text: usageLine.label
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: usageLine.emphasized
        elide: Text.ElideRight
      }

      Text {
        id: usageFigure
        textFormat: Text.PlainText
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: usageLine.figure
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: usageLine.emphasized
        horizontalAlignment: Text.AlignRight
      }
    }

    Text {
      id: usageNote
      textFormat: Text.PlainText
      visible: usageLine.note !== ""
      anchors.top: usageRow.bottom
      anchors.topMargin: Style.space(1)
      anchors.left: parent.left
      width: parent.width
      text: usageLine.note
      color: root.dim
      opacity: 0.75
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
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
    // What this one record holds: its own ledger and the counts beside it. A
    // binding over the loaded record, so it is recomputed when the card's
    // provider is replaced, not once per frame.
    readonly property var usageRows: root.providerUsageRows(provider)

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

    // ---------- usage ----------
    // The figures come first, because they are what the card was opened to see,
    // and they are drawn in the same family as the block under the list: what
    // this one account has spent, then the counts its collector keeps beside
    // the tokens. Every line comes from the record, so an agent that reports a
    // balance and nothing else opens to its links alone and no empty heading.
    Column {
      id: usageSection
      visible: providerDetails.usageRows.length > 0
      width: parent.width
      spacing: Style.space(2)

      PanelSectionHeader {
        text: "Usage · all time"
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Repeater {
        model: providerDetails.usageRows

        UsageLine {
          required property var modelData
          width: usageSection.width
          label: modelData.label
          figure: modelData.figure
        }
      }
    }

    // Then the way out: the page with the numbers this record cannot read, and
    // the one thing every provider has.
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
    readonly property bool hovered: rowHover.containsMouse || gripHover.hovered
    // A card in flight lifts: dimmed and a hair larger, which reads as "held"
    // without a copy of it having to chase the pointer through a positioner.
    readonly property bool lifted: root.isDragging(provider) && root.dragFromCard

    opacity: lifted ? 0.72 : 1
    scale: lifted ? 1.02 : 1

    Behavior on opacity { NumberAnimation { duration: 120 } }
    Behavior on scale { NumberAnimation { duration: 120 } }

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

      // ---------- the handle ----------
      // The mark and the name are what you grab. The meters on the right are not
      // part of it: they are the numbers, and a gesture that started on a bar
      // would be a gesture about a bar. Everything a drag needs to know about
      // the list is decided here, before the Flickable is asked to give up the
      // pointer, so a scroll that begins over a figure still scrolls.
      Item {
        id: grip
        // The right edge stops where the meters start. It is expressed as a
        // width, not as an anchor to `trailing`: `trailing` belongs to
        // `summary`, and Qt refuses an anchor to anything that is not a parent
        // or a sibling — silently, leaving this item zero wide. A zero-wide
        // handle is an invisible one: no hand cursor, no drag, no nothing.
        // Measuring the same edge as a number keeps both ends where the layout
        // put them.
        anchors.left: parent.left
        anchors.top: parent.top
        // The summary row only: an open card's buttons are not a handle, and a
        // grip stretched over them would turn a drag that started on a button
        // into a drag about the card.
        anchors.bottom: summary.bottom
        // A card with no meters and no balance has nothing in `trailing`, so
        // measuring to it yields zero and the whole logo-and-name area stops
        // being a handle. Fall back to the full row: a card with no figure to
        // protect is entirely grip.
        width: trailing.x > 0 ? trailing.x : parent.width
        // The hand cursor is chosen by paint order, so this has to stay above
        // the card's click target rather than merely after it in the file.
        z: 1

        HoverHandler {
          id: gripHover
          cursorShape: gripDrag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        }

        DragHandler {
          id: gripDrag
          // Nothing follows the pointer: the card is one cell of a positioner,
          // and moving it would re-lay out the list it is describing. The lift
          // on the card and the seam drawn over the list do the talking instead.
          target: null
          // Vertical only, so a sideways swipe across the name is still a swipe.
          xAxis.enabled: false
          // The press belongs to the card's own click target until this decides
          // it has become a drag.
          grabPermissions: PointerHandler.CanTakeOverFromAnything

          onActiveChanged: {
            if (active) {
              root.beginDrag(providerRow.provider, true)
              // Put the seam where the drag started, so the first answer is
              // already on screen when the card lifts.
              root.updateDrag(centroid.scenePosition)
            } else {
              root.endDrag()
            }
          }
          // `centroid`, not `point`: the single-point `point` property is not in
          // scope inside a handler and reads as an error, which silently killed
          // every update after it — the drag never worked out a drop slot at all.
          onActiveTranslationChanged: if (active) root.updateDrag(centroid.scenePosition)
          onCanceled: root.resetDrag()
        }
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
      // No cursor here on purpose: this is the whole mark, and the grab hand
      // from the handler below has to win. A cursor set on a child beats the
      // parent's handler, so setting one here would hide the hand.
      onClicked: root.toggleExpanded(linkedButton.provider ? linkedButton.provider.providerId : "")
    }

    // A mark is small enough that all of it is the handle: dragging one up out
    // of the row is the only way back to a card, so there is no corner of it
    // left over for something else. A drag that lands back in the row changes
    // nothing, which is why only the upward direction is wired to anything.
    DragHandler {
      id: markDrag
      target: null
      xAxis.enabled: false
      grabPermissions: PointerHandler.CanTakeOverFromAnything

      onActiveChanged: {
        if (active) {
          root.beginDrag(linkedButton.provider, false)
          root.updateDrag(centroid.scenePosition)
        } else {
          root.endDrag()
        }
      }
      // `centroid`, not `point`: see the note on the card's handler.
      onActiveTranslationChanged: if (active) root.updateDrag(centroid.scenePosition)
      onCanceled: root.resetDrag()
    }

    // The cursor belongs to this handler, not to the MouseArea above: a child
    // that sets a cursor is resolved before its parent's handlers are, so the
    // mark kept showing the click hand instead of the grab hand.
    HoverHandler {
      cursorShape: markDrag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
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
