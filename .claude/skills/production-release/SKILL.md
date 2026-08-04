---
name: production-release
description: How to release this WordPress+Docker stack to production self-hosted, using a Cloudflare Zero Trust Tunnel as the reverse proxy in front of Nginx (no open ports, no local TLS certs). Use when asked to deploy to production, go live, set up Cloudflare Tunnel, or expose this stack to the internet. Distinct from the separate FTP-deploy path documented for the theme-only production repo.
---

# Production release via Cloudflare Zero Trust Tunnel

This is the self-hosted production path for *this* repo: the same `nginx` + `php` + `db` stack
as local dev, with a `cloudflared` container tunneling public traffic to `nginx` over the
internal Docker network. Cloudflare terminates TLS at its edge, so no certificates or open
inbound ports are needed on the host. This is unrelated to the separate FTP theme-deploy repo
described in the README's "Production Repo Workflow" section — don't mix the two up.

## 1. Create the tunnel in Cloudflare (one-time, per domain)

1. Log in to the [Cloudflare Zero Trust dashboard](https://one.dash.cloudflare.com/) for the
   account that owns the domain.
2. Go to **Networks → Tunnels → Create a tunnel**, choose **Cloudflared** as the connector type,
   name it (e.g. the project name), and continue.
3. On the "Install and run a connector" step, copy the **tunnel token** shown (a long string
   passed to `cloudflared tunnel run --token ...`) — you won't need to install `cloudflared`
   locally, it already runs in the `docker-compose.prod.yml` container.
4. Add a **Public Hostname**: pick the subdomain/domain to expose, service type **HTTP**, URL
   **`http://nginx:80`** (the compose service name, resolved over the internal Docker network —
   not `localhost` and not the `NGINX_PORT` host mapping).
5. Save. Cloudflare automatically creates the DNS record for that hostname.

## 2. Configure this repo's `.env`

Set on the production host:

```
CLOUDFLARE_TUNNEL_TOKEN=<token copied in step 1.3>
PRODUCTION_DOMAIN=<the public hostname from step 1.4, e.g. example.com>
```

Also review before going live:
- `MYSQL_ROOT_PASSWORD` / `MYSQL_USER` / `MYSQL_PASSWORD` are **not** the `.env.example`
  placeholder values (`root` / `wpuser` / `wppassword`) — set strong, unique production
  credentials.
- Consider `make env-encrypt` if `.env` needs to be committed anywhere for this host.

## 3. Bring up the production stack

```bash
make prod-up
```

This runs `docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d`, which adds
the `cloudflared` service and swaps nginx's config to `nginx/production.conf` (security headers,
gzip, rate-limited `wp-login.php`, real IP trust from `cloudflared`). It refuses to start if
`CLOUDFLARE_TUNNEL_TOKEN` isn't set.

## 4. Verify

- `make prod-logs` — confirm `cloudflared` logs show the tunnel connector registering
  successfully (look for "Registered tunnel connection").
- `make prod-ps` — all services should be `Up`/healthy.
- Visit `https://<PRODUCTION_DOMAIN>` — should reach WordPress through the tunnel.

## 5. Point WordPress at the production domain

If this is a fresh install, run the install wizard at `https://<PRODUCTION_DOMAIN>` directly
(DB host is still `db`). If migrating an existing `siteurl`/`home`, update them via WP-CLI so
serialized data updates correctly:

```bash
make wp-cli CMD="option update siteurl https://<PRODUCTION_DOMAIN>"
make wp-cli CMD="option update home https://<PRODUCTION_DOMAIN>"
```

Recommended `wp-config.php` hardening for production (Cloudflare already provides TLS, so trust
its forwarded scheme):

```php
define( 'WP_DEBUG', false );
define( 'DISALLOW_FILE_EDIT', true );
define( 'FORCE_SSL_ADMIN', true );
if ( isset( $_SERVER['HTTP_X_FORWARDED_PROTO'] ) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https' ) {
    $_SERVER['HTTPS'] = 'on';
}
```

## 6. Rollback / take down

```bash
make prod-down
```

Stops the production stack (`nginx`, `php`, `db`, `cloudflared`) without touching the `db_data`
volume. To go back to local dev conventions, just use `make up`/`make down` as before — the two
compose files are independent overlays, never mixed automatically.
