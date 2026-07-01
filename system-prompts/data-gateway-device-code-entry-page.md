<!--
name: 'Data: Gateway device code entry page'
description: >-
  HTML verification page served at a gateway device endpoint, prompting the user
  to enter the short device code shown by Claude Code so they can sign in
  through their company identity provider
ccVersion: 2.1.195
variables:
  - ERROR_CARD_BLOCK
-->
<span class="status warn">Connect device</span>
<h1>Enter the code from your device.</h1>
<p class="sub">Claude Code shows a short code when you sign in. Enter it here to connect — then you'll sign in with your company identity provider.</p>
<form method="post" action="/device">
  <input class="code-input" name="user_code" inputmode="latin" autocomplete="off" autocapitalize="characters" autocorrect="off" spellcheck="false" placeholder="XXXX-XXXX" maxlength="9" autofocus required>
  <button class="go" type="submit">Continue</button>
</form>
${ERROR_CARD_BLOCK}
