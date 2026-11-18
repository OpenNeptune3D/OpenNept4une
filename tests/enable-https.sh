#!/usr/bin/env bash
# Enable HTTPS for Fluidd/Moonraker via nginx and a local certificate.
# Let's Encrypt cannot sign 10.211.55.x / LAN IPs. This uses a self-signed cert
# with IP and hostname SANs. Browsers will warn until you trust the cert.
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
    echo "Error: run with sudo:  sudo $0" >&2
    exit 1
fi

die() { echo "Error: $*" >&2; exit 1; }
ok() { echo "==> $*"; }

TARGET_USER="${SUDO_USER:-mks}"
if [[ "$TARGET_USER" = "root" ]]; then
    TARGET_USER="mks"
fi
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6 || true)"
[[ -n "$TARGET_HOME" ]] || TARGET_HOME="/home/${TARGET_USER}"
FLUIDD_DIR="${FLUIDD_DIR:-${TARGET_HOME}/fluidd}"
[[ -d "$FLUIDD_DIR" ]] || die "Fluidd not found at ${FLUIDD_DIR}"

CERT_DIR="${CERT_DIR:-/etc/ssl/opennept4une}"
CERT="${CERT_DIR}/opennept4une.crt"
KEY="${CERT_DIR}/opennept4une.key"
DAYS="${CERT_DAYS:-825}"
REDIRECT_HTTP="${REDIRECT_HTTP:-true}"

hostname_fqdn="$(hostname -f 2>/dev/null || hostname)"
hostname_short="$(hostname)"
mapfile -t ipv4s < <(hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true)

ok "Creating certificate in ${CERT_DIR}"
mkdir -p "$CERT_DIR"
chmod 755 "$CERT_DIR"

san="DNS:localhost,DNS:${hostname_short},DNS:${hostname_fqdn},IP:127.0.0.1"
for ip in "${ipv4s[@]+"${ipv4s[@]}"}"; do
    [[ -n "$ip" ]] || continue
    san="${san},IP:${ip}"
done

tmp_cfg="$(mktemp)"
cat > "$tmp_cfg" <<EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = ${hostname_short}
O = OpenNept4une sandbox

[v3_req]
subjectAltName = ${san}
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
basicConstraints = CA:false
EOF

openssl req -x509 -nodes -days "$DAYS" -newkey rsa:2048 \
    -keyout "$KEY" \
    -out "$CERT" \
    -config "$tmp_cfg"
rm -f "$tmp_cfg"
chmod 640 "$KEY"
chmod 644 "$CERT"
chown root:www-data "$KEY" || chown root:root "$KEY"

ok "Writing nginx TLS site (SAN: ${san})"
http_block=""
if [[ "$REDIRECT_HTTP" = "true" ]]; then
    http_block=$(cat <<'HTTP'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    return 301 https://$host$request_uri;
}
HTTP
)
else
    http_block=$(cat <<HTTP
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    root ${FLUIDD_DIR};
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location /websocket {
        proxy_pass http://127.0.0.1:7125/websocket;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
    }

    location ~ ^/(printer|api|access|machine|server)/ {
        proxy_pass http://127.0.0.1:7125\$request_uri;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
HTTP
)
fi

cat > /etc/nginx/sites-available/fluidd <<EOF
${http_block}

server {
    listen 443 ssl http2 default_server;
    listen [::]:443 ssl http2 default_server;
    server_name _;
    root ${FLUIDD_DIR};
    index index.html;

    ssl_certificate ${CERT};
    ssl_certificate_key ${KEY};
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location /websocket {
        proxy_pass http://127.0.0.1:7125/websocket;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
        proxy_read_timeout 86400;
    }

    location ~ ^/(printer|api|access|machine|server)/ {
        proxy_pass http://127.0.0.1:7125\$request_uri;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 86400;
    }
}
EOF

rm -f /etc/nginx/sites-enabled/default
ln -sfn /etc/nginx/sites-available/fluidd /etc/nginx/sites-enabled/fluidd
nginx -t
systemctl reload nginx

moon_conf="${TARGET_HOME}/printer_data/config/moonraker.conf"
if [[ -f "$moon_conf" ]]; then
    ok "Ensuring Moonraker CORS allows https for this host"
    extra=("*://localhost" "*://localhost:*" "*://${hostname_short}" "*://${hostname_fqdn}")
    for ip in "${ipv4s[@]+"${ipv4s[@]}"}"; do
        [[ -n "$ip" ]] || continue
        extra+=("*://${ip}" "*://${ip}:*")
    done
    for origin in "${extra[@]}"; do
        if ! grep -Fq "$origin" "$moon_conf"; then
            awk -v orig="$origin" '
                BEGIN { added=0 }
                { print }
                $0 ~ /^cors_domains:/ && !added { print "    " orig; added=1 }
            ' "$moon_conf" > "${moon_conf}.tmp"
            mv "${moon_conf}.tmp" "$moon_conf"
        fi
    done
    chown "${TARGET_USER}:${TARGET_USER}" "$moon_conf"
    systemctl restart moonraker.service || true
fi

primary_ip="${ipv4s[0]:-localhost}"
echo
ok "HTTPS is enabled"
echo "Open:  https://${primary_ip}/"
echo "Cert:  ${CERT}"
echo
echo "The browser will warn because this is a self-signed cert (Let's Encrypt"
echo "cannot sign a Parallels 10.211.55.x address). Click Advanced → Proceed."
echo
echo "To trust it on the Mac (one time):"
echo "  scp ${TARGET_USER}@${primary_ip}:${CERT} /tmp/opennept4une.crt"
echo "  sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain /tmp/opennept4une.crt"
