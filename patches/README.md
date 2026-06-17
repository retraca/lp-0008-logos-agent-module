# Patches

## liblogosdelivery-lightpush-legacy-codec.patch
The published `delivery_module` ships `liblogosdelivery` v0.38.1, which dials waku
lightpush with the modern codec `/vac/waku/lightpush/3.0.0`. Every nwaku relay node
tested (v0.24–v0.33) registers only the **legacy** handler
`/vac/waku/lightpush/2.0.0-beta1` as a live libp2p stream (3.0.0 appears in identify
metadata but is not a real handler), so multistream-select fails and the module's own
`send()` never reaches the relay.

This patch switches `liblogosdelivery`'s send path to `WakuLegacyLightPushClient` /
`WakuLegacyLightPushCodec`, matching what the relays actually serve. Rebuild:

```
nix build .../logos-delivery-module \
  --override-input logos-delivery path:<patched-logos-delivery>
```

After the patched dylib is deployed, the module-driven cross-node send negotiates
cleanly and the message reaches the subscriber (see docs/EVIDENCE_PEERS.md:
msg_hash matches across sender → nwaku → receiver). Cross-node *receive* (filter)
already worked unpatched. This is an upstream fix for the platform delivery module,
included here for reproducibility.
