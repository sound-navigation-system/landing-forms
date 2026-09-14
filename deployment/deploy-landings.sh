#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY="$SCRIPT_DIR/deploy-landing.sh"
TARGET="${1:-all}"

deploy_ngopie() {
    "$DEPLOY" \
        --repo https://github.com/sound-navigation-system/ngopie.com.ua.git \
        --ref main \
        --source . \
        --destination /var/www/ngopie.com.ua/public_html \
        --url https://ngopie.com.ua \
        --check css/styled.css \
        --check img/header_logo.svg \
        --check index.js
}

deploy_sns() {
    GIT_SSH_COMMAND="ssh -i /home/edvin/.ssh/id_ed25519_sns_website_deploy -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/home/edvin/.ssh/known_hosts" \
    "$DEPLOY" \
        --repo git@github.com:sound-navigation-system/sns-website.git \
        --ref main \
        --source public_html \
        --destination /var/www/sns.co.ua/public_html \
        --url https://sns.co.ua \
        --check assets/css/main.css \
        --check assets/img/logo.png \
        --check assets/js/main.js
}

case "$TARGET" in
    ngopie) deploy_ngopie ;;
    sns) deploy_sns ;;
    all) deploy_ngopie; deploy_sns ;;
    *) echo "Usage: sudo $0 [all|ngopie|sns]" >&2; exit 2 ;;
esac
