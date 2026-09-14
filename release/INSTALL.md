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

## Update

Replace the complete `humalike` directory with one verified release, then run:

```text
refresh
restart humalike
```

Never combine files from different versions.

## Rollback

Keep the previous verified archive. Replace the complete resource with that
version, run `refresh`, and restart `humalike`. Credentials remain in
`server.cfg` and are not part of release archives.
