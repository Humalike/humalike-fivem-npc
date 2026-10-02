# Install HumaLike for FiveM

1. Verify `humalike.zip` using the adjacent `.sha256` file.
2. Extract the included `humalike` directory into your FXServer resources directory.
3. Copy the required values from `humalike.example.cfg` into `server.cfg`.
4. Keep the license behind `set`, never `setr`.
5. Run `refresh`, then `ensure humalike`.

`ensure humalike` fails closed when the control plane does not return complete
edge and voice assignment identities. Check the startup log, fix the
control-plane rollout, then run `ensure humalike` again.

The resource works standalone. ESX, QBCore, Qbox, inventory and interaction
providers are optional and selected independently. Keep custom adapters in a
separate resource so updating HumaLike is always a complete directory
replacement.

The NUI is already built and included in the archive. Server owners do not need
Node.js or pnpm to install a release.

For configuration and framework guides, visit
https://docs.humalike.com/ai-npc.

## Automatic updates

On every start HumaLike checks for a newer release, installs it and restarts
itself. Each update is signed by HumaLike and verified before any file is
written; an update that fails verification is never installed. To let the
resource restart itself, add these four lines to `server.cfg` (`ensure` runs
`stop` and `start` on the resource's behalf):

```cfg
add_ace resource.humalike command.refresh allow
add_ace resource.humalike command.ensure allow
add_ace resource.humalike command.stop allow
add_ace resource.humalike command.start allow
```

Without these lines the update is still downloaded and applies on the next
server restart.

| Setting | Effect |
| --- | --- |
| `set humalike_auto_update auto` | Default. Install new releases on start. |
| `set humalike_auto_update notify` | Only print that a release is available. |
| `set humalike_auto_update off` | Never check. |
| `set humalike_version "0.6.0"` | Stay on exactly this version, installing it if needed. Use it to roll back. |

Run `humalike_update` in the server console to check and install right away.
The files that an update replaced are kept in
`humalike/.humalike-update/previous` until the next update.

## Manual update

Replace the complete `humalike` directory with one verified release, then run:

```text
refresh
restart humalike
```

Never combine files from different versions.

## Rollback

Set `humalike_version` to the previous version and restart the server, or keep
the previous verified archive, replace the complete resource with that
version, run `refresh`, and restart `humalike`. Credentials remain in
`server.cfg` and are not part of release archives.
