# LP-0008 demo, narration script

Read this over the silent screencast (`docs/lp0008-f8-linux-demo.mp4`, 1920x1080, ~7 min).
Everything runs for real on a local LEZ chain; every proof is real, RISC0_DEV_MODE=0. The
on-screen comment before each command is the short version; say it in your own words. Assumes
the viewer knows Logos Core, modules, and shielded accounts. Pause on any step.

The prize requires your narration. A silent screencast is not sufficient.

## intro
"LP-0008 is an autonomous agent that runs as a native Logos Core module. It holds its own
shielded LEZ wallet, stores files on Logos Storage, finds other agents over Logos Messaging,
and pays them within limits its owner sets. This is the whole flow on one machine, every
proof real."

1. "A standalone LEZ sequencer with real proving. The chain produces blocks; you can see the
   height climb."
2. "agent up is the whole deploy in one command: it starts Logos Core headless, loads the
   agent next to the platform modules, and sets the owner and the spending limit. Five
   modules, zero crashes, platform modules untouched."
3. "The agent owns a shielded LEZ account; its identity is an npk. Its A2A Agent Card carries
   the same npk, so a peer that discovers the card knows which account to pay."
4. "Twenty-one skills behind a documented interface."
5. "The owner funds it: a hundred LEZ, public to private. Watch the zkVM run. Those execution
   times are the per-operation compute cost, which is the performance evidence."
6. "The file vault. The agent runs an embedded Logos Storage node. The owner hands it a file;
   the agent stores it and returns a content address. Anyone can retrieve it later by that
   address, byte for byte. This is a real Codex upload and download, not a stub."
7. "A second agent comes online with its own shielded account."
8. "The two agents publish their Agent Cards to a shared Logos Messaging topic and read each
   other. Agent A finds agent B and its skills."
9. "The owner set a fifty LEZ limit. Agent A opens a task priced eighty, over the limit. It
   does not pay. It retried notifying the owner three times, reports it could not reach them,
   and holds the spend. Agent A still has all hundred LEZ. Above the limit never executes."
10. "Five LEZ is under the limit, so the agent pays the peer itself, with a real proof. A goes
   to ninety-five, B to five."
11. "Restart the agent. The held task and the config come back. No state lost."
12. "Call a skill with bad input. It returns an error and the module keeps running."

## close
"That is the agent end to end: it loads with the platform modules unchanged, owns and funds
its own account, deploys in one command, stores and retrieves files on Logos Storage, runs
the full agent-to-agent flow over real messaging and a real payment, enforces the spending
gate, survives a restart, and isolates skill failures. Every proof real. The hosted-testnet
agents and the Basecamp owner UI are in the repo evidence."
