# HumaLike adapter template

Copy this directory into a new resource, rename it, and replace the placeholder
callbacks with translations for your server. Keep the adapter separate from the
`humalike` resource so upgrades cannot overwrite server-specific behavior.

The server and client register again after every
`humalike:integration:ready` event, so either resource can restart first.

`client_audiohub.lua` is an optional adapter for servers that run a
shared-microphone (audio hub) resource; delete it if yours does not.
