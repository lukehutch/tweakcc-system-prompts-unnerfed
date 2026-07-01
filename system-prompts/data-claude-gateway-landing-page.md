<!--
name: 'Data: Claude gateway landing page'
description: >-
  HTML status page served at a Claude Code gateway root, showing the gateway
  logo, the running gateway URL, the identity-provider host, an OAuth discovery
  link, and the gateway version
ccVersion: 2.1.195
variables:
  - GATEWAY_ASCII_LOGO
  - GATEWAY_URL
  - IDENTITY_PROVIDER_HOST
  - HTML_ESCAPE_FN
  - GATEWAY_VERSION
-->
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>Claude gateway for Amazon Bedrock, Google Cloud, and Microsoft Foundry</title>
</head>
<body style="font-family: monospace; margin: 1em;">
<pre style="line-height: 1; margin: 0 0 1em 0;">${GATEWAY_ASCII_LOGO}</pre>
<pre style="margin: 0;">
<b>Claude gateway for Amazon Bedrock, Google Cloud, and Microsoft Foundry</b>

Running at ${GATEWAY_URL}

To connect from Claude Code:
  Your admin provisions this gateway URL via managed settings
  (forceLoginGatewayUrl) — then /login connects here directly.

Identity provider   ${IDENTITY_PROVIDER_HOST}
Discovery           <a href="/.well-known/oauth-authorization-server">/.well-known/oauth-authorization-server</a>
Version             ${HTML_ESCAPE_FN(GATEWAY_VERSION)}
</pre>
</body>
</html>
