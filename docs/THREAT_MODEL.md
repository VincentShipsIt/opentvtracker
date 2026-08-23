# Threat model

## Assets and adversaries

Protected assets include provider spend/quota, App Attest keys and receipts, user OpenRouter keys, personal viewing data, notes, diary entries, partner membership, CloudKit share URLs, signing material, and server configuration.

Expected adversaries include automated scrapers, replay attackers, modified or forked clients, users extracting a public app's network protocol, compromised provider keys, malicious imported files, and accidental credential publication. App Attest raises the cost of automated hosted-proxy abuse; it does not make a compromised device trustworthy forever.

## Trust boundaries

| Boundary                 | Data allowed                                             | Controls                                                                                                                                                             |
| ------------------------ | -------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Local SwiftData          | Personal library, diary, lists, and preferences          | Local model, versioned archive, user-initiated export                                                                                                                |
| Invitation-only CloudKit | Shared list, profiles, activity, events, reactions, notes, tombstones, title metadata, shared custom lists | Custom zone, stable IDs, CKShare, outbox, revocation/leave purge                                                                                                     |
| Nearby partner pairing   | Short-lived CloudKit invitation URL                      | User-initiated Bonjour discovery, local-only peer connection, six-digit TLS pre-shared key, payload validation, session ends with the pairing screen                 |
| Official proxy           | Bounded catalog/cinema query plus App Attest headers     | HTTPS, official App ID validation, persisted key/counter, one-time challenge, signed payload, short token, per-device/IP quota, strict schemas, timeout, kill switch |
| Direct OpenRouter        | User key, at most 20 public candidates, and viewingProfile | OAuth PKCE, associated HTTPS callback, Keychain, explicit opt-in, timeout, strict output IDs, deterministic fallback                                                 |
| Public providers         | TV search or official cinema page                        | Keyless fallback, timeout, source attribution                                                                                                                        |
| External links           | User-selected TMDB/IMDb/cinema URL                       | User gesture and external site's policy                                                                                                                              |
| App Group widgets        | Bounded Up Next / upcoming snapshot                      | App Group `group.dev.opentvtracker.app`, no credentials or CloudKit identifiers                                                                                      |

## Abuse cases and mitigations

- **Copied app protocol:** production verifies Apple's certificate chain and the configured App ID; public forks cannot mint accepted keys.
- **Captured attestation/assertion:** challenges expire after roughly one minute and are consumed once; assertions bind the exact request and require a monotonically increasing counter.
- **Stolen short token:** a token expires quickly and is useless without the Secure Enclave key and a fresh assertion.
- **Attestation farming:** registration has a strict per-IP hourly quota, persisted keys cannot silently change public key, registration has a kill switch, and operators can add Apple fraud-receipt assessment if needed.
- **Provider-cost amplification:** endpoint-specific per-device and per-IP quotas, bounded page/query/date/region input, upstream timeouts, post-auth cache, edge rate limits, dedicated read-only TMDB key, monitoring, and kill switches.
- **Unsupported/simulator bypass:** production has no bypass; development requires an explicit secret and receives one quarter of normal origin quotas.
- **CORS confusion:** native auth is App Attest; CORS is optional and does not affect authorization.
- **Log exfiltration:** structured logs use path only and exclude query, IP, headers, body, secrets, assertions, receipts, and personal fields.
- **Malicious library import:** selected files are size-preflighted and read through a capped stream; JSON/CSV records, fields, and nesting plus ZIP entries and expansion are bounded; duplicate recognized TV Time paths are rejected; and imported auto-loaded artwork is limited to supported catalog image hosts before persistence.
- **Operator-funded AI abuse:** the server has no OpenRouter credential or reranking endpoint; users pay through their own capped key.
- **Nearby invitation interception:** pairing advertises only while the owner keeps the screen open; the invitation travels over TLS authenticated by the displayed code and is accepted through the existing CloudKit flow.

## Residual risks

Apple and provider availability can interrupt features. A compromised unlocked device can access app-visible data and ask the Secure Enclave to sign requests. App Attest has platform and quota limits. Official production uses PostgreSQL (`DATABASE_URL`) for verified device keys and counters. The file-backed device store is a residual risk only when a self-hosted instance runs without `DATABASE_URL` and therefore depends on a correctly mounted single-writer disk. IP quotas can affect shared networks. Public catalog data can still be copied from legitimate devices. External providers observe requests made directly to them, including OpenRouter `viewingProfile` summaries when the user enables reranking.

Operational controls and incident steps are in [PROVIDER_OPERATIONS.md](PROVIDER_OPERATIONS.md).
