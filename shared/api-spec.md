# BHNM API Specification (BeNeM-consumed subset)

This is the narrower "which endpoints does BeNeM actually use" layer on top
of the full BHNM reference. For the full API surface, see
`BHNM_API_REFERENCE.md` in this directory.

## Base URLs

- Legacy API: `https://<BHNM_HOST>/fw/index.php?r=restful/`
- Open 3.0 API: `https://<BHNM_HOST>/api/`

## Authentication

- `password` — API key (stored in `NetreoAPIConfiguration.apiKey` on iOS)
- `pin` — Optional PIN (stored in `NetreoAPIConfiguration.pin` on iOS)

## Endpoints used by BeNeM

| Endpoint | Method | Consumer | Notes |
|---|---|---|---|
| | | | |

_Populate this table as features land. See `ios/CLAUDE.md` for the full current endpoint list used by the iOS app._
