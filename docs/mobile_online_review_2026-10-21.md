# Independent online transport review — 2026-10-21

Reviewed `network_session.gd`, `network_match.gd`, and their payment, population, placement, research, and destruction callees. The review covered client packet shapes, peer lifecycle, sender ownership, fog checks, and server-authoritative transactions. It did not use the public matchmaking arena or run a penetration test.

## Two reproduced defects, now fixed

1. **Malformed Repeat flags caused a server script error.** The command validator accepted an array or object in `enabled`; `bool(packet.enabled)` then raised `Invalid call. Nonexistent 'bool' constructor.` Godot 4.6 reproduced the invalid conversion, and a separate direct validator probe confirmed `{"command":"repeat","enabled":[]}` returned true before the fix. The networking agent added a `TYPE_BOOL` check. The same independent probe now returns false. This was a remotely triggerable script error; no process crash was demonstrated.

2. **A terminal event during initial map loading lost the result screen.** Delivering `matched` immediately followed by `ended` before the deferred Main scene attached left transport state `ended`, an attached adapter, and gameplay state `PLAYING` (2). The networking agent now retains the terminal result or connection failure, applies it after the pending snapshot on attachment, skips the ready message, and prevents a late started message from reopening the session. The unchanged independent real-scene probe now reaches `GAME_OVER` (4). The repository loading-terminal regression also passes its connection-failure variant with the correct result reason, pending snapshot, defeat state, and no gameplay command acceptance.

## Other checks

- Numeric payload shape probes reject object/array unit IDs, building type, and queue index, and reject infinite positions. Parsing an intentionally excessive exponent emits Godot's expected warning before validation rejects the resulting infinite position.
- Sender ownership is derived from the server's matched peer list; selected entities and building transactions are checked against that owner. No client-supplied resource balance, population allowance, price, or winner is trusted.
- Training delegates to the existing paid population-reservation transaction; cancellation refunds actual queued items; placement rechecks visible legal ground and a reachable worker before spending; research uses its existing eligibility/payment transaction.
- No additional actionable ownership/payment or peer-lifecycle defect was found in this bounded review. This does not establish security against every possible malformed packet or service-level denial of service.

The separate selection-death test was migrated to tap the new Train page. It passes all twelve phone/scale/notch profiles while preserving its original checks: partial and final selection deaths retain the management surface, the pre-death touch coordinate buys exactly one Villager, Clear refunds exactly, and no world command leaks.
