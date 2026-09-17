// Injected into every web tab (isolated world) to notice submitted login
// forms, so Silo can offer to save them in its vault. Runs after
// qwebchannel.js; talks to WebPage's `siloCapture` bridge object.
(function () {
  if (window.__siloCaptureInstalled || typeof QWebChannel === 'undefined' || typeof qt === 'undefined') return;
  window.__siloCaptureInstalled = true;

  let bridge = null;
  let lastSent = '';
  new QWebChannel(qt.webChannelTransport, function (channel) { bridge = channel.objects.siloCapture; });

  function visible(el) {
    if (!el || el.disabled) return false;
    const r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0;
  }

  // Username: the last visible text/email field before the password field
  // (same form when there is one), else the value remembered from a previous
  // step (sites that ask for the e-mail first).
  let rememberedUser = '';
  function usernameFor(pw) {
    const scope = pw.form || document;
    const inputs = Array.prototype.slice.call(scope.querySelectorAll(
      'input:not([type]), input[type=text], input[type=email], input[type=tel]'));
    let user = null;
    inputs.forEach(function (t) {
      if (t.autocomplete === 'one-time-code' || /otp|code|captcha|search/i.test(t.name + ' ' + t.id)) return;
      if (!t.value) return;
      if (t.compareDocumentPosition(pw) & Node.DOCUMENT_POSITION_FOLLOWING) user = t;
    });
    if (user) return user.value.trim();
    return rememberedUser;
  }

  document.addEventListener('input', function (e) {
    const t = e.target;
    if (!t || t.tagName !== 'INPUT') return;
    if ((t.type === 'email' || ((t.type === 'text' || !t.type) && /user|email|login|account|identifier|mail/i.test(
        t.name + ' ' + t.id + ' ' + t.autocomplete))) && t.value) {
      rememberedUser = t.value.trim();
    }
  }, true);

  function capture(reason) {
    const passwords = Array.prototype.slice.call(document.querySelectorAll('input[type=password]')).filter(visible);
    // Registration / change-password forms show two password fields: skip them.
    if (passwords.length !== 1) return;
    const pw = passwords[0];
    if (!pw.value || pw.autocomplete === 'new-password') return;
    const username = usernameFor(pw);
    const key = location.host + '|' + username + '|' + pw.value;
    if (key === lastSent) return;
    lastSent = key;
    if (bridge) bridge.captured(location.href, username, pw.value, reason);
  }

  document.addEventListener('submit', function () { capture('submit'); }, true);
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Enter' && e.target && e.target.tagName === 'INPUT') capture('enter');
  }, true);
  // SPAs without <form>: a click on a submit-looking control while a password is typed
  document.addEventListener('click', function (e) {
    const el = e.target && e.target.closest ? e.target.closest('button, input[type=submit], [role=button]') : null;
    if (!el) return;
    if (el.type === 'submit' || /log ?in|sign ?in|continue|next|submit|connect|connexion|se connecter|valider|entrar|anmelden/i.test(
        (el.textContent || '') + ' ' + (el.value || '') + ' ' + (el.getAttribute('aria-label') || ''))) {
      capture('click');
    }
  }, true);
})();
