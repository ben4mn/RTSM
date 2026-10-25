# Protocol 6: Scout vision compatibility

Beta9 requires network protocol **6** because Scout vision changes from 8 to 10 tiles and clients compute fog from their local unit data. Match snapshots do not carry a vision override. Allowing a protocol 5 client to join the new authority would therefore produce inconsistent fog. The map catalog stays **3**; packet formats, action timing and authority rules are unchanged.

The existing version mismatch paths ask players to reload. Cached beta8 remains usable for offline Solo, but it must update before joining a protocol 6 online match. This change does not reload a running match.

## Verification

The historical filenames `tools/run_protocol3_compatibility.py` and `tools/test_online_protocol3_client_compatibility.gd` are retained. The runner now derives the older protocol and catalog from a supplied immutable source tree rather than assuming protocol 2. It also accepts an explicit current source tree.

On 25 October 2026, the loopback suite passed against frozen beta8 commit `9176284ece56572169306c156ecd05e7f4848842` (protocol 5) and checkpoint `5ce41d49f30621bce0294ad9744e06758dac28e4` (protocol 6). It recorded 49 sent/received events and verified:

- Old protocol 5 search, host and join requests receive explicit reload errors from the new authority. The same sockets can recover by submitting current requests, and rejected guests do not alter the protected room.
- Missing, fractional, string, Boolean and future protocol requests cannot enter a room or queue. Ping confirms that ignored malformed packets do not simply kill the socket.
- Two valid protocol 6 peers retain their selected civilizations, enter the same match with opposite slots, and receive started messages and nonempty authoritative snapshots.
- The actual current Godot client sends protocol 6 to the frozen old authority and receives an explicit reload error. Its 34-check fixture also rejects old, missing, fractional, string, Boolean and nonfinite room/matched replies, while accepting integral JSON `6.0`.
- Original and private runtime sources remain unchanged, preferences are isolated, and every owned process exits.

These are actual headless Godot and loopback WebSocket checks, not browser or public-server tests. Final public acceptance must use the release artifact and is recorded separately.

## Deployment helper binding

New copies in the release task's `work/protocol6-helpers` preserve previous helper bytes except the exact supported-protocol tuple additions and the new guard digest pinned by postflight. The stage helper is byte-identical. Idle checks, request binding, rollback validation, health checks and activation receipt requirements are unchanged. Root independently confirmed the allowed substitutions; 25 helper tests pass, including malformed type rejection, embedded smoke functions, exact pin binding and prior protocol 5 rollback readiness.

| Helper | SHA-256 |
| --- | --- |
| `guarded_deploy_remote_v7.py` | `b768a412b392b5f416e3cb11e489d48949391ed5acbe2671272984664fc53d85` |
| `smoke_match_server_candidate_v5.py` | `abcd2b9c8648d1f89cbbc024fd6a645f811f567c3ccb6afb13037a257c2a212b` |
| `public_postflight_release_v4.py` | `948c662a2af1c0934bc2fbf3fe235ef94e6c8c61cb5fb9ad6c0c2b5f250a34e4` |
| `stage_web_release.py` | `431ba98a91dd93bc1f501b9eac2160621feedf52df6ff94edf2d6da0cb35df71` |

The existing public private-room verification path is `tools/run_online_tests.py --rooms-only`, which invokes `tools/test_online_rooms.gd`. Its 40 checks read protocol and catalog constants from the frozen game source, so no protocol allowlist change is needed. It covers all three maps, host authority, capacity, replacement guests, cancellation, initial populations, snapshots and disconnect results. Reply type validation is covered by the compatibility fixture above. The unrelated historical protocol 2/3 browser-evidence parser remains unchanged.

Detailed receipts, source archive hashes, logs and the helper diff are retained in the release task's `outputs/beta9-protocol6`. This document records compatibility evidence; it does not assert deployment or final public verification.
