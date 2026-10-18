# GLOT Remote security model

Phase 1 is a local pairing and command channel. It does not move the pointer, inject keys, launch apps, or read the clipboard.

## Scope

- Both apps talk only on the local network. There is no account, cloud relay, or port-forward helper.
- The Mac listener binds through Network.framework and advertises `_glotremote._tcp` only while Listening is on.
- Loopback tests bind `127.0.0.1` and do not advertise Bonjour.
- One iPhone session is accepted at a time. Extra connections are cancelled.
- The Mac can disconnect the session immediately. Revoke blocks that iPhone until Forget removes the record.

## Transport

- TLS 1.3 only. Session tickets are disabled. The Mac presents a self-signed P-256 certificate whose SAN is `glotremote.local`, and the client sets that name as SNI.
- The certificate is not accepted from a public CA. During a first pairing the client accepts the peer key it observes, then both people compare a code. After pairing, the client requires the same observed key. On the macOS 27 Network stack that key is a 91-byte SubjectPublicKeyInfo whose last 65 bytes are the uncompressed P-256 point announced in the handshake. A different size is rejected.
- The iPhone stores its P-256 signing key in the data-protection keychain (`com.glot.remote`, After First Unlock, This Device Only, not synchronizable). The Mac companion is sandboxed and does not have a keychain-access-groups entitlement, so the same data-protection call returns errSecMissingEntitlement. The Mac stores its TLS key and certificate in its login keychain instead. Items are not synchronizable. Queries set `LAContext.interactionNotAllowed` so a missing item fails instead of prompting.
- Paired device records live in Application Support JSON with directory mode `0700` and file mode `0600`. They are not secrets by themselves. The TLS private key and the iPhone signing key are not in those files.

## Pairing

The six-digit code is the first 4 bytes of SHA-256 over:

`GLOTRemote-pair-v1 || Mac P-256 point || iPhone 64-byte signing key || client nonce || server nonce`

The code is shown on both screens. It is not sent on the wire. Both sides must explicitly accept before `pairResult` succeeds. A mismatch, denial, or expiry stores nothing.

This is a short authentication string, not a typed PIN. A person who does not compare the screens can approve a different key. The apps do not claim the first pairing is safe without that comparison. CryptoKit cannot do the point arithmetic SPAKE2 needs, so SPAKE2 is not implemented.

An iPhone with no saved pin always asks to pair, even if the Mac already has a record. A revoked iPhone is rejected and does not get a new pairing dialog until Forget. A different signing key for a known iPhone is rejected. The stored key is not replaced.

## After pairing

Reconnect authentication is an ECDSA signature over:

`GLOTRemote-auth-v1 || server challenge || Mac key || client nonce || server nonce || iPhone UUID`

The signature is P-256 DER. Handshake and later messages carry UUIDs. The Mac drops a repeated id. Frames are length-prefixed, rejected above 65,536 bytes, and rate-limited to 40 messages per second. Eight invalid commands end the session. Heartbeats run every 5 seconds. A session with no inbound traffic for 16 seconds ends. The iPhone retries a dropped saved session with delays of 1, 2, 4, 8, then 15 seconds, up to 8 attempts. Pairing denial, expiry, and TLS failure do not retry.

Control messages defined for later phases are validated and then rejected as unsupported. They are not injected. There is no shell channel and no path that launches an arbitrary command.

## Logs

Session logs use subsystem `com.glot.remote` and record state changes only. Pairing codes, keys, nonces, signatures, and clipboard text are not logged. Phase 1 has no clipboard feature.

## What this build does not protect against

- A person at the Mac who approves a code they did not compare.
- Malware already running as the logged-in user. The companion is a normal user-space app.
- A later phase that posts input events. Those need Accessibility and are not implemented here.
