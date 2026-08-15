#!/usr/bin/env bash

set -Eeuo pipefail

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run this script with sudo." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="/etc/landing-forms.env"

for command_name in python3 apache2ctl a2enconf systemctl curl; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "Required command is missing: $command_name" >&2
        exit 1
    }
done

install -d -m 755 -o root -g root /opt/landing-forms
install -m 755 -o root -g root "$SCRIPT_DIR/app.py" /opt/landing-forms/app.py
install -m 644 -o root -g root \
    "$SCRIPT_DIR/landing-forms.service" \
    /etc/systemd/system/landing-forms.service
install -m 644 -o root -g root \
    "$SCRIPT_DIR/landing-forms-apache.conf" \
    /etc/apache2/conf-available/landing-forms.conf

if [[ ! -f "$ENV_FILE" ]]; then
    read -r -s -p "Google app password for mike.hrafin@gmail.com: " APP_PASSWORD
    echo
    if [[ -z "$APP_PASSWORD" ]]; then
        echo "The app password cannot be empty." >&2
        exit 1
    fi
    APP_PASSWORD="${APP_PASSWORD// /}"
    umask 077
    {
        echo "PORT=3001"
        echo "ALLOWED_ORIGINS=https://ngopie.com.ua,https://www.ngopie.com.ua"
        echo "SMTP_HOST=smtp.gmail.com"
        echo "SMTP_PORT=465"
        echo "SMTP_USER=mike.hrafin@gmail.com"
        printf 'SMTP_PASSWORD=%s\n' "$APP_PASSWORD"
        echo "MAIL_TO=mgrafin@gmail.com"
    } > "$ENV_FILE"
    chown root:root "$ENV_FILE"
    chmod 600 "$ENV_FILE"
else
    echo "Keeping existing $ENV_FILE"
fi

a2enconf landing-forms >/dev/null
systemctl daemon-reload
systemctl enable --now landing-forms.service
apache2ctl configtest
systemctl reload apache2

curl --fail --silent --show-error http://127.0.0.1:3001/health
echo
echo "Landing forms service installed and healthy."
