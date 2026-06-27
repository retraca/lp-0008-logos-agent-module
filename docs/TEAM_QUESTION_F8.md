# F8 questions — ATTACH TO THE SUBMISSION PR (do not wait for a Discord answer)

**Precedent (Discord, 2026-06-23):** another builder, degenjef (LP-0017), hit the *exact same*
macOS wall — *"There's no macOS-arm64 Logos Delivery/Waku binary published, so I can't run a
live Delivery node on my build machine. Is a Linux-run Delivery demo acceptable...?"* — and
**attached that question to his submission PR (#96)** rather than waiting. hackyguru (helper)
confirmed the process: submit the PR, core contributors review and answer technical questions.
macOS is a known-painful platform for this stack (romthpt: Metal-toolchain sandbox issue building
wallet-ffi; devisha.eth/arseniy.eth: macOS build problems). So our F8 macOS limitation is a
recognized platform reality, not a credibility problem — the move is to be transparent in the PR
and ask, exactly like degenjef.

Put the two questions below in the PR body (and/or post in Discord). F8 is a hard, un-relaxed
criterion, so we want the reviewers' call on the evidence bar; we have a real platform bug
localized precisely (with a partial fix + offer to upstream).

Note on #2's GUI sub-question: the spec already mostly answers it — Supportability requires
the demo video to *"show terminal output"*, and Basecamp appears only under Usability
(*"local build instructions and loadable assets are provided"*), not as a required GUI
recording. So the open part is just whether the first demo needs the full discover→task→pay
loop or a signed lifecycle is enough to start.

---

**Draft message:**

> Hi — LP-0008 (autonomous agent module). Two things before I submit:
>
> **1. Cross-module event receive doesn't work under `qt_remote` (the default logoscore
> transport) on macOS — I've localized it and have a partial fix.** A subscribing module never
> receives another module's `messageReceived`. Two findings:
> (a) `RemoteLogosObject::onEvent` (logos-protocol `remote_transport.cpp`) connects to the
> dynamic replica's `eventResponse` signal *before* the replica initializes, so the connect
> no-ops — I patched it to connect after `QRemoteObjectReplica::initialized()` and verified the
> connect then succeeds (`eventResponse` is present in the replica meta, `connect()` returns true).
> (b) Even so, no event is delivered: with two agents peered and cards relaying, delivery's source
> emits the signal ("ModuleProxy: forwarding event as Qt signal") but it never reaches the agent's
> replica over QtRO IPC. So the remaining failure is **source→replica signal forwarding**, not the
> consumer connect. **Is cross-module event subscription expected to work under logoscore today,
> and on which OS/transport did you last verify a module receiving another module's event?** The
> in-process `Local` transport connects to the real proxy and works; `qt_remote` IPC is where it
> breaks. Happy to share the patch + a one-command repro.
>
> **2. F8 evidence bar + Linux demo.** Given there's no macOS-arm64 Delivery/Waku binary and the
> qt_remote event issue above, **is a Linux-run two-agent F8 demo acceptable** (the module/SDK code
> is real and tested), the way a Linux-run Delivery demo was raised for LP-0017? And does the first
> review need the full live discover→task→pay loop (agent A ingesting agent B's published Agent Card
> over Messaging, then task + autonomous LEZ payment), or is a signed A2A task lifecycle over Logos
> Messaging enough to start? I have card publish, the A2A task lifecycle, and autonomous LEZ payment
> from the agent's own shielded funds all working with real proofs (`RISC0_DEV_MODE=0`); the only
> piece gated on the bug above is one agent *receiving* the other's card over the discovery topic.

---

**Why this framing:** #1 is now a precise, credible bug report (consumer fix done + verified,
remaining failure localized to host-side QtRO forwarding) plus an offer to upstream — that builds
trust and forces a concrete answer on whether/where event-receive works. #2 gets the substance bar
in writing: if a signed lifecycle is enough to start, we already pass F8 in substance; if full live
ingest is required, we need a Linux (or Local-transport) run confirmed first.

**Do not assume PR #66 covers F8** — that relaxation is the *adoption* criterion (our F10), not F8.
