#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage:
  sudo ./deploy-landing.sh \
    --repo REPOSITORY_URL \
    --ref BRANCH_OR_TAG \
    --source RELATIVE_SOURCE_DIR \
    --destination WEB_ROOT \
    --url PUBLIC_URL \
    [--check RELATIVE_URL]...

Example:
  sudo ./deploy-landing.sh \
    --repo https://github.com/example/site.git \
    --ref main \
    --source . \
    --destination /var/www/example/public_html \
    --url https://example.com \
    --check css/style.css \
    --check img/logo.svg
EOF
}

REPO=""
REF=""
SOURCE=""
DESTINATION=""
PUBLIC_URL=""
CHECKS=()

while (($#)); do
    case "$1" in
        --repo) REPO="${2:-}"; shift 2 ;;
        --ref) REF="${2:-}"; shift 2 ;;
        --source) SOURCE="${2:-}"; shift 2 ;;
        --destination) DESTINATION="${2:-}"; shift 2 ;;
        --url) PUBLIC_URL="${2:-}"; shift 2 ;;
        --check) CHECKS+=("${2:-}"); shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

for command_name in git rsync curl find; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "Required command is missing: $command_name" >&2
        exit 1
    }
done

if [[ -z "$REPO" || -z "$REF" || -z "$SOURCE" || -z "$DESTINATION" || -z "$PUBLIC_URL" ]]; then
    usage >&2
    exit 2
fi

if [[ "$DESTINATION" != /var/www/*/public_html ]]; then
    echo "Refusing unexpected destination: $DESTINATION" >&2
    exit 1
fi

TEMP_DIR="$(mktemp -d)"
cleanup() {
    rm -rf -- "$TEMP_DIR"
}
trap cleanup EXIT

CHECKOUT="$TEMP_DIR/repository"
STAGING="$TEMP_DIR/staging"

echo "Fetching $REPO ($REF) ..."
git clone --quiet --depth 1 --branch "$REF" --single-branch "$REPO" "$CHECKOUT"

SOURCE_PATH="$CHECKOUT/$SOURCE"
if [[ ! -d "$SOURCE_PATH" || ! -f "$SOURCE_PATH/index.html" ]]; then
    echo "Deployment source does not contain index.html: $SOURCE_PATH" >&2
    exit 1
fi

mkdir -p "$STAGING"
rsync -a --delete \
    --exclude '.git/' \
    --exclude '.deployment/' \
    "$SOURCE_PATH/" "$STAGING/"

SOURCE_FILES="$(find "$STAGING" -type f | wc -l | tr -d ' ')"
if [[ "$SOURCE_FILES" -lt 2 ]]; then
    echo "Refusing to deploy only $SOURCE_FILES file(s)." >&2
    exit 1
fi

mkdir -p "$DESTINATION"
rsync -a --delete "$STAGING/" "$DESTINATION/"
find "$DESTINATION" -type d -exec chmod 755 {} +
find "$DESTINATION" -type f -exec chmod 644 {} +
chown -R www-data:www-data "$DESTINATION"

DESTINATION_FILES="$(find "$DESTINATION" -type f | wc -l | tr -d ' ')"
if [[ "$SOURCE_FILES" != "$DESTINATION_FILES" ]]; then
    echo "File-count verification failed: source=$SOURCE_FILES destination=$DESTINATION_FILES" >&2
    exit 1
fi

CONTENT_DIFFERENCES="$(
    rsync -rnic --delete \
        --out-format='%i %n%L' \
        "$STAGING/" "$DESTINATION/"
)"
if [[ -n "$CONTENT_DIFFERENCES" ]]; then
    echo "Content verification failed after synchronization:" >&2
    printf '%s\n' "$CONTENT_DIFFERENCES" >&2
    exit 1
fi

echo "Checking ${PUBLIC_URL%/}/ ..."
curl --fail --silent --show-error --location --max-time 20 \
    --output /dev/null "${PUBLIC_URL%/}/"

for relative_url in "${CHECKS[@]}"; do
    relative_url="${relative_url#/}"
    echo "Checking ${PUBLIC_URL%/}/$relative_url ..."
    curl --fail --silent --show-error --location --max-time 20 \
        --output /dev/null "${PUBLIC_URL%/}/$relative_url"
done

COMMIT="$(git -C "$CHECKOUT" rev-parse --short=12 HEAD)"
echo "Deployment completed: $COMMIT, $DESTINATION_FILES files, HTTP checks passed."
