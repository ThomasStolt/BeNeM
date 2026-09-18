# BHNM bug report — `ha_status_api.php` rejects HTTPS requests as non-HTTPS

*For the BHNM development team. Not a BeNeM item.*

**Summary:** `/api/ha_status_api.php` answers `"API require HTTPS connection."` to a request made
over real HTTPS, and ignores `X-Forwarded-Proto`. Behind a TLS-terminating reverse proxy or load
balancer — a normal enterprise deployment — the endpoint is unusable. Other API endpoints on the
same host, same request style, same credential, work correctly.

**Version:** BHNM 26.3.01. **Measured:** 2026-09-18.
**Host:** `bhnm-b.tstolt.com`, reached directly over TLS. No proxy of ours is in the path for the
measurements below.

---

### 1. Real HTTPS request, no extra headers

```
curl -sk -X POST https://bhnm-b.tstolt.com/api/ha_status_api.php \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data 'password=<API_KEY>'

HTTP 200, 55 bytes, Content-Type: text/html; charset=UTF-8
a:1:{s:5:"Error";s:29:"API require HTTPS connection.";}
```

The request *is* HTTPS. The scheme is `https`, TLS was negotiated, and the response arrived over
that same connection.

### 2. Identical request with `X-Forwarded-Proto: https`

```
curl -sk -X POST https://bhnm-b.tstolt.com/api/ha_status_api.php \
  -H 'X-Forwarded-Proto: https' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data 'password=<API_KEY>'

HTTP 200, 55 bytes
a:1:{s:5:"Error";s:29:"API require HTTPS connection.";}
```

Byte-identical. The header is not consulted.

### 3. Control — another endpoint on the same host, same connection style, same key

```
curl -sk -X POST https://bhnm-b.tstolt.com/api/incident_api.php \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data 'pwd=<API_KEY>&method=getincidents'

HTTP 200, 1921 bytes, valid JSON
{"result":"completed","active_incidents":[{"title":"Threshold ADSL Upload Speed ...
```

So the host, the TLS setup and the credential are all fine. The behaviour is specific to
`ha_status_api.php`.

---

### Why this matters

1. **The HTTPS check is wrong even with no proxy involved.** Case 1 is a direct TLS request and it
   still fails, so whatever the endpoint tests, it is not "was this request encrypted".
2. **`X-Forwarded-Proto` is ignored**, so the standard remedy behind a load balancer does not work
   either. Any deployment that terminates TLS ahead of the application — most enterprise ones —
   cannot use this endpoint at all.
3. **The failure is silent by HTTP standards: `200 OK`.** A client checking status codes sees
   success. The error is only in the body.
4. **The body is PHP-serialized, not JSON**, while `incident_api.php` on the same host returns
   JSON. A client cannot parse both with one code path.

### What would fix it

Trust the terminating proxy's `X-Forwarded-Proto` when present, fall back to the direct connection
scheme, and return the API's normal JSON error shape with a 4xx status rather than `200` plus a
PHP-serialized string.

### Impact on us

`ha_status_api.php` is unusable, so our connection test now probes `incident_api.php` instead.
Not blocking — reported because it will affect any customer behind a load balancer.
