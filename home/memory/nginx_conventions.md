---
name: Nginx conventions
description: TLS cert paths, post-renewal deploy hook template, reverse-proxy vhost templates, and vhost rules
type: user
---

# Nginx & TLS Conventions

## TLS Certificates — Let's Encrypt

Cert path is always `/etc/letsencrypt/live/domain/` — `domain` is the **literal directory name**, not a variable or the actual hostname. Never substitute a real domain name here.

```
/etc/letsencrypt/live/domain/
  cert.pem        — leaf certificate only
  chain.pem       — intermediate chain only
  fullchain.pem   — cert + chain (use this for ssl_certificate)
  privkey.pem     — private key (use this for ssl_certificate_key)
```

Always reference:
```nginx
ssl_certificate     /etc/letsencrypt/live/domain/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/domain/privkey.pem;
```

### Let's Encrypt Post-Renewal Hook

When a cert or key must be copied to another location (e.g. a service that cannot read from `/etc/letsencrypt/` directly), create a deploy hook at `/etc/letsencrypt/renewal-hooks/deploy/{project_name}.sh`:

```sh
#!/bin/sh
# Deploy hook for {project_name} — runs after every successful renewal

DEST_CERT="/etc/{project_name}/tls/fullchain.pem"
DEST_KEY="/etc/{project_name}/tls/privkey.pem"

\mkdir -p "$(dirname -- "$DEST_CERT")"
\cat /etc/letsencrypt/live/domain/fullchain.pem > "$DEST_CERT"
\cat /etc/letsencrypt/live/domain/privkey.pem  > "$DEST_KEY"
\chmod 600 "$DEST_KEY"
\chmod 644 "$DEST_CERT"

# Reload/restart depending on service type — use whichever applies:
# systemd service
\systemctl reload nginx

# Docker Compose service (run from compose file directory)
\docker compose -f /opt/{project_name}/compose.yml restart

# Single Docker container
\docker restart {project_name}-app
```

Hook file must be executable (`chmod 755`). Never use `cp` — `cat >` preserves permissions correctly. Always `chmod 600` the key.

---

## Nginx Vhost Files

Location: `/etc/nginx/vhosts.d/{hostname}.conf`

### Reverse Proxy Vhost

```nginx
# reverse proxy for {hostname}

server {
  listen                                    443 ssl;
  listen                                    [::]:443 ssl;
  server_name                               {hostname};
  access_log                                /var/log/nginx/access.{hostname}.log;
  error_log                                 /var/log/nginx/error.{hostname}.log info;
  keepalive_timeout                         75 75;
  client_max_body_size                      0;
  chunked_transfer_encoding                 on;
  add_header Strict-Transport-Security      "max-age=31536000; includeSubDomains";
  ssl_protocols                             TLSv1.2 TLSv1.3;
  ssl_ciphers                               ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
  ssl_prefer_server_ciphers                 off;
  ssl_session_cache                         shared:SSL:10m;
  ssl_session_timeout                       1d;
  ssl_certificate                           /etc/letsencrypt/live/domain/fullchain.pem;
  ssl_certificate_key                       /etc/letsencrypt/live/domain/privkey.pem;

  location / {
    send_timeout                            3600;
    proxy_connect_timeout                   3600;
    proxy_send_timeout                      3600;
    proxy_read_timeout                      3600;
    proxy_http_version                      1.1;
    proxy_buffering                         off;
    proxy_request_buffering                 off;
    proxy_ssl_verify                        off;
    proxy_set_header Host                   $host;
    proxy_set_header X-Real-IP              $remote_addr;
    proxy_set_header X-Forwarded-For        $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto      $scheme;
    proxy_set_header X-Forwarded-Scheme     $scheme;
    proxy_set_header X-Forwarded-Port       $server_port;
    proxy_set_header Upgrade                $http_upgrade;
    proxy_set_header Connection             $connection_upgrade;
    proxy_set_header Accept-Encoding        "";
    proxy_redirect                          http:// https://;
    proxy_pass                              http://172.17.0.1:{port};
  }

  include /etc/nginx/global.d/*.conf;
}
```

### Rules

- **TLS 1.2 + 1.3 only** — never TLSv1.0 or TLSv1.1 (deprecated, insecure)
- **`ssl_prefer_server_ciphers off`** — modern recommendation; lets the client pick from the safe suite
- **`client_max_body_size 0`** — no limit; set per-location if restriction is needed
- **All timeouts 3600** — covers large uploads and slow connections
- **`proxy_buffering off` + `proxy_request_buffering off`** — required for streaming, WebSockets, and large uploads
- **`proxy_ssl_verify off`** — upstream is `172.17.0.1` (local), cert verification is unnecessary overhead
- **Per-vhost logs** — `access.{hostname}.log` and `error.{hostname}.log info`; never share the default log across vhosts
- **HSTS** — `max-age=31536000; includeSubDomains` (1 year); use `max-age=7200` only during initial setup/testing
- **`proxy_pass` always to `http://172.17.0.1:{port}`** — never `localhost`, `127.0.0.x`, or `0.0.0.0`
- **`include /etc/nginx/global.d/*.conf`** — always include at end of server block
- **No HTTP (port 80) block** — HTTP redirect is handled globally, not per-vhost
