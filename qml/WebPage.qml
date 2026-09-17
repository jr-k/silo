import QtQuick
import QtWebChannel
import QtWebEngine

// Browser page of a "web" tab.
WebEngineView {
    id: page
    property string tabUrl: ""
    // Restored tabs load lazily, the first time they are shown.
    property bool loaded: false

    readonly property string kind: "web"
    readonly property string displayUrl: String(url)

    profile: WebProfile

    // Login submitted in the page and not yet saved / dismissed:
    // {url, host, username, password, existingId, reason}
    property var pendingCapture: null
    function clearCapture() { pendingCapture = null }

    // capture.js (isolated world) reports submitted login forms here.
    webChannel: captureChannel
    webChannelWorld: WebEngineScript.ApplicationWorld
    Component.onCompleted: {
        var scripts = []
        for (var i = 0; i < 2; ++i) {
            var script = WebEngine.script()
            script.name = i === 0 ? "qwebchannel" : "silo-capture"
            script.sourceUrl = i === 0 ? "qrc:///qtwebchannel/qwebchannel.js" : "qrc:/web/capture.js"
            script.injectionPoint = WebEngineScript.DocumentReady
            script.worldId = WebEngineScript.ApplicationWorld
            script.runOnSubframes = true
            scripts.push(script)
        }
        userScripts.collection = scripts
    }
    QtObject {
        id: captureBridge
        WebChannel.id: "siloCapture"
        function captured(url, username, password, reason) {
            if (!password || vault.locked || vault.neverSave(url))
                return
            var existing = vault.findLogin(url, username)
            // Already stored as is: nothing to offer
            if (existing.id && vault.get(existing.id).password === password)
                return
            page.pendingCapture = { url: url, host: vault.hostOf(url), username: username, password: password,
                                    existingId: existing.id || "", reason: reason }
        }
    }
    WebChannel {
        id: captureChannel
        registeredObjects: [captureBridge]
    }
    // A capture is only relevant for a while: drop it on the next site change.
    onUrlChanged: if (pendingCapture && vault.hostOf(String(url)) !== pendingCapture.host) pendingCapture = null

    // 2FA code armed by a login fill, typed into the one-time-code field as
    // soon as one shows up (same page or the next step), for two minutes.
    // {code, epoch, secret, source, id}: vault logins carry the secret so the
    // code is always fresh; connector codes are re-fetched once they roll over.
    property var pendingTotp: null
    property bool totpRefreshing: false
    signal totpFilled()

    function armTotp(credentials) {
        if (!credentials || (!credentials.totp && !credentials.totpSecret)) {
            disarmTotp()
            return
        }
        pendingTotp = { code: credentials.totp || "", epoch: Math.floor(Date.now() / 30000),
                        secret: credentials.totpSecret || "", source: credentials.source || "", id: credentials.id || "" }
        totpRefreshing = false
        totpPoll.restart()
        totpExpiry.restart()
        tryFillTotp()
    }
    function disarmTotp() {
        pendingTotp = null
        totpRefreshing = false
        totpPoll.stop()
        totpExpiry.stop()
    }
    // Current code, or "" when the connector code expired and must be re-fetched
    function currentTotp() {
        if (!pendingTotp)
            return ""
        if (pendingTotp.secret)
            return vault.totpCode(pendingTotp.secret)
        return Math.floor(Date.now() / 30000) === pendingTotp.epoch ? pendingTotp.code : ""
    }
    function tryFillTotp() {
        if (!pendingTotp || loading)
            return
        var code = currentTotp()
        runJavaScript("(" + totpFillSource + ")(" + JSON.stringify(code) + ")", function(result) {
            if (!page.pendingTotp || !result || !result.found)
                return
            if (result.filled) {
                page.disarmTotp()
                page.totpFilled()
            } else if (!code && !page.totpRefreshing && page.pendingTotp.source && page.pendingTotp.source !== "vault") {
                page.totpRefreshing = true
                passwords.fetch(page.pendingTotp.source, page.pendingTotp.id)
            }
        })
    }
    Timer { id: totpPoll; interval: 700; repeat: true; onTriggered: page.tryFillTotp() }
    Timer { id: totpExpiry; interval: 120000; onTriggered: page.disarmTotp() }
    onLoadingChanged: if (!loading && pendingTotp) tryFillTotp()
    Connections {
        target: passwords
        enabled: page.totpRefreshing
        function onCredentialsReady(credentials) {
            if (!page.pendingTotp || credentials.id !== page.pendingTotp.id)
                return
            page.totpRefreshing = false
            var pending = page.pendingTotp
            pending.code = credentials.totp || ""
            pending.epoch = Math.floor(Date.now() / 30000)
            page.pendingTotp = pending
            if (pending.code)
                page.tryFillTotp()
            else
                page.disarmTotp()
        }
        function onErrorChanged() { if (page.pendingTotp && passwords.errors[page.pendingTotp.source]) page.disarmTotp() }
    }

    function ensureLoaded() {
        if (loaded)
            return
        loaded = true
        url = tabUrl
    }
    function openExternally() { Qt.openUrlExternally(url) }

    // Fills the login form of the page: the visible password field and the
    // text/email field before it (or the focused field). Sites that ask for
    // the username first get just that; call again on the password step.
    // callback({user: bool, password: bool})
    function fillCredentials(username, password, callback) {
        var script = "(" + fillSource + ")(" + JSON.stringify(username || "") + ", " + JSON.stringify(password || "") + ")"
        runJavaScript(script, function(result) { if (callback) callback(result || {}) })
    }
    // Kept as source text: compiled QML functions do not stringify.
    readonly property string fillSource: `function(u, p) {
        function visible(el) {
            var r = el.getBoundingClientRect(), s = getComputedStyle(el)
            return r.width > 0 && r.height > 0 && s.visibility !== "hidden" && s.display !== "none" && !el.disabled && !el.readOnly
        }
        function setValue(el, v) {
            if (!el) return false
            el.focus()
            var proto = Object.getPrototypeOf(el)
            var desc = Object.getOwnPropertyDescriptor(proto, "value")
            if (desc && desc.set) desc.set.call(el, v); else el.value = v
            el.dispatchEvent(new Event("input", { bubbles: true }))
            el.dispatchEvent(new Event("change", { bubbles: true }))
            return true
        }
        var passwords = Array.prototype.slice.call(document.querySelectorAll("input[type=password]")).filter(visible)
        var texts = Array.prototype.slice.call(document.querySelectorAll(
            "input:not([type]), input[type=text], input[type=email], input[type=tel]")).filter(visible)
            .filter(function(e) { return e.autocomplete !== "one-time-code" && !/otp|code|captcha|search/i.test(e.name + " " + e.id) })
        var pwEl = passwords[0] || null, userEl = null
        if (pwEl) {
            var form = pwEl.form
            texts.forEach(function(t) {
                if ((!form || t.form === form) && (t.compareDocumentPosition(pwEl) & Node.DOCUMENT_POSITION_FOLLOWING))
                    userEl = t
            })
            if (!userEl) texts.forEach(function(t) { if (t.compareDocumentPosition(pwEl) & Node.DOCUMENT_POSITION_FOLLOWING) userEl = t })
        } else {
            userEl = texts.filter(function(t) {
                return /user|email|login|account|identifier|mail/i.test(t.name + " " + t.id + " " + t.autocomplete + " " + (t.placeholder || ""))
            })[0] || texts[0] || null
        }
        var active = document.activeElement
        if (active && active.tagName === "INPUT") {
            if (active.type === "password") pwEl = active
            else if (!pwEl && ["text", "email", "tel", ""].indexOf(active.type) >= 0) userEl = active
        }
        var result = { user: false, password: false }
        if (u && userEl) result.user = setValue(userEl, u)
        if (p && pwEl) result.password = setValue(pwEl, p)
        if (pwEl && result.password) pwEl.focus(); else if (userEl && result.user) userEl.focus()
        return result
    }`

    // Finds the one-time-code input(s) of the page and types the code in.
    // Handles a single field and split "one box per digit" inputs. With an
    // empty code only reports whether a field is there. -> {found, filled}
    readonly property string totpFillSource: `function(code) {
        function visible(el) {
            var r = el.getBoundingClientRect(), s = getComputedStyle(el)
            return r.width > 0 && r.height > 0 && s.visibility !== "hidden" && s.display !== "none" && !el.disabled && !el.readOnly
        }
        function setValue(el, v) {
            el.focus()
            var proto = Object.getPrototypeOf(el)
            var desc = Object.getOwnPropertyDescriptor(proto, "value")
            if (desc && desc.set) desc.set.call(el, v); else el.value = v
            el.dispatchEvent(new Event("input", { bubbles: true }))
            el.dispatchEvent(new Event("change", { bubbles: true }))
            el.dispatchEvent(new KeyboardEvent("keyup", { bubbles: true }))
        }
        function label(el) {
            var texts = [el.name, el.id, el.autocomplete, el.placeholder, el.getAttribute("aria-label")]
            if (el.labels) Array.prototype.forEach.call(el.labels, function(l) { texts.push(l.textContent) })
            return texts.join(" ")
        }
        var otpRe = /otp|totp|2fa|mfa|one.?time|verification|verif|authenticat|security.?code|passcode|\\bpin\\b|\\btoken\\b|\\bcode\\b/i
        var noiseRe = /search|zip|postal|promo|coupon|country|phone|referr|invite|discount|captcha/i
        var inputs = Array.prototype.slice.call(document.querySelectorAll("input")).filter(function(e) {
            return ["", "text", "tel", "number", "password"].indexOf(e.type || "") >= 0 && visible(e)
        })
        var otp = inputs.filter(function(e) {
            if (e.autocomplete === "one-time-code") return true
            var l = label(e)
            return otpRe.test(l) && !noiseRe.test(l)
        })
        // Split inputs: one character each, 4 to 8 boxes
        var boxes = inputs.filter(function(e) { return e.maxLength === 1 && e.type !== "password" })
        if (boxes.length >= 4 && boxes.length <= 8 && (otp.length === 0 || otp.every(function(e) { return boxes.indexOf(e) >= 0 })))
            otp = boxes
        if (otp.length === 0) return { found: false, filled: false }
        if (!code) return { found: true, filled: false }
        if (otp.length > 1 && otp.every(function(e) { return e.maxLength === 1 })) {
            var n = Math.min(code.length, otp.length)
            for (var i = 0; i < n; ++i) setValue(otp[i], code.charAt(i))
            otp[n - 1].focus()
            return { found: true, filled: true }
        }
        setValue(otp[0], code)
        return { found: true, filled: true }
    }`

    onTabUrlChanged: if (loaded) url = tabUrl

    onNewWindowRequested: function(request) {
        // Popups (OAuth, target=_blank) stay in this tab for now.
        request.openIn(this)
    }
}
