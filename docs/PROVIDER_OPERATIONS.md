# Provider operations and incident controls

## Least privilege and budgets

- Use one dedicated TMDB API Read Access Token for this proxy. Do not reuse account-management, build, CI, or unrelated application credentials.
- The server must not have `OPENROUTER_API_KEY`. Each user authorizes a separate OpenRouter key through OAuth PKCE.
- OpenRouter users should set a small key-specific USD limit and a daily or monthly reset in the OpenRouter key settings. Check `limit`, `limit_remaining`, `usage_daily`, and `usage_monthly` through OpenRouter's current-key view. A revoked or exhausted key only disables optional reranking.
- Keep Apple signing keys, DeviceCheck keys, distribution certificates, and credential exports outside the repository and deployment image.

## Monitoring

- Alert on TMDB `401`, `429`, and sustained `5xx` responses, rising upstream latency, and changes in request volume/cost. Review the TMDB account/dashboard and Render metrics at least weekly during beta.
- Alert on registration spikes, App Attest rejection rates, replay/counter failures, origin `429`s, state-persistence errors, and persistent-disk capacity.
- Keep safe structured logs only. Never temporarily log headers, bodies, assertions, challenges, receipts, query values, keys, tokens, or IP addresses during an incident.
- Add coarse edge limits in front of Render. Suggested starting ceilings per IP: challenge 30/minute, registration 5/hour, catalog search 30/minute, external-ID lookup 60/minute, title lookup 120/minute, and cinema 40/minute. Origin limits remain authoritative and include stricter per-device ceilings.
- The TVDB resolver caches only unique confirmed mappings for seven days. Misses and ambiguous provider responses are not cached, so monitor repeated `catalog-resolve` 404s separately from upstream failures.

## Rotation

### TMDB

1. Create a replacement dedicated read token.
2. Update only `TMDB_READ_ACCESS_TOKEN` in the deployment secret store.
3. Restart the service and confirm generic health plus an App Attest-authenticated catalog request.
4. Revoke the old token and watch `401`/`429` metrics.

### App Attest service tokens

Changing `APP_ATTEST_TOKEN_SECRET` invalidates all short-lived service tokens. Clients refresh by signing a token challenge with the persisted device key. Rotate during a quiet window and retain the device state file.

### OpenRouter user key

The user disconnects OpenRouter in the app, revokes the old key in OpenRouter, sets a daily/monthly cap, and reconnects. No server change is involved.

## Kill switches

- `PROXY_ENABLED=false` — stop challenge/registration/token/catalog/cinema service globally.
- `CATALOG_ENABLED=false` — stop TMDB access; apps use TVmaze fallback.
- `CINEMA_ENABLED=false` — stop proxied Embassy fetches; apps use official direct source behavior.
- `APP_ATTEST_REGISTRATION_ENABLED=false` — freeze new device registrations while existing attested devices continue.
- Edge/WAF rule — block an abusive IP/range or route before Render.
- Provider console — revoke the TMDB token if exposure or uncontrolled spend is suspected.

## Incident sequence

1. Disable the affected route or global proxy; do not deploy unrelated code.
2. Revoke/rotate any potentially exposed provider credential.
3. Preserve safe metrics and deployment audit history; do not copy secrets into tickets or chat.
4. Determine whether abuse came through registration, a valid attested device, a bypass misconfiguration, edge behavior, or provider-key exposure.
5. Delete compromised device records only when necessary; those installations will need a new App Attest key.
6. Restore service gradually with registration disabled, lower edge limits, and monitoring.
7. Record the incident and rotate adjacent credentials if scope is uncertain.
