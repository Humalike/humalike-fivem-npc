# Install HumaLike for FiveM

1. Verify `humalike.zip` using the adjacent `.sha256` file.
2. Extract the included `humalike` and `humalike-updater` directories into your
   FXServer resources directory.
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

On every start HumaLike checks for a newer release and installs it. Each update
is signed by HumaLike and verified before any file is written; an update that
fails verification is never installed. The new version goes live immediately
only when `humalike-updater` is started with the grants below; otherwise it
applies on the next server restart.

The archive includes a second, small resource, `humalike-updater`, which only
restarts `humalike` after an update (a resource cannot safely restart itself).
Put it next to `humalike` and add to `server.cfg`, before `ensure humalike`:

```cfg
ensure humalike-updater
add_ace resource.humalike-updater command.refresh allow
add_ace resource.humalike-updater command.ensure allow
add_ace resource.humalike-updater command.stop allow
add_ace resource.humalike-updater command.start allow
```

Without these lines the update is still installed and applies on the next
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

Set `humalike_auto_update off`, stop `humalike` and `humalike-updater` (or the
server), replace both directories with one verified release, then run:

```text
refresh
ensure humalike-updater
ensure humalike
```

Never combine files from different versions.

## Rollback

Set `humalike_version` to the previous version, for example
`set humalike_version "0.5.1"`, and restart the server. HumaLike installs that
version and stays on it until you remove the setting. Replacing the folder by
hand is undone on the next start while automatic updates are on, so pin the
version (or set `humalike_auto_update off`) first. Credentials remain in
`server.cfg` and are not part of release archives.
