#!/usr/bin/env bash
# install.sh — Install HomeHub via docker-compose
set -euo pipefail

# Generate per-instance secrets into .env before anything reads it.
# Idempotent: an existing non-empty value is left alone, so a re-run does not
# invalidate data already written under the old value.
af_gen_secret() {
    local key="$1" value
    if [ -n "$(sed -n "s/^${key}=//p" .env | head -1)" ]; then
        return 0
    fi
    # Hex from /dev/urandom: no openssl dependency, no '$' for Compose to interpolate.
    value="$(od -An -tx1 -N32 /dev/urandom | tr -d ' \n')"
    if grep -q "^${key}=" .env; then
        sed -i "s|^${key}=.*|${key}=${value}|" .env
    else
        printf '%s=%s\n' "$key" "$value" >>.env
    fi
}

af_gen_secret SECRET_KEY

set -a
source .env
set +a

mkdir -p /opt/homehub/uploads /opt/homehub/media /opt/homehub/pdfs /opt/homehub/data

# Write config.yml on first install. password is left blank — HomeHub's own
# "leave blank for password-less access" mode — since basic_auth: true on the
# Traefik port is the actual access control. Idempotent: an existing config is
# left alone so user customisations (family members, theme, etc.) survive re-runs.
if [ ! -f /opt/homehub/config.yml ]; then
    cat > /opt/homehub/config.yml << 'CFGEOF'
instance_name: "HomeHub"
password: ""
admin_name: "Administrator"
feature_toggles:
  shopping_list: true
  media_downloader: true
  pdf_compressor: true
  qr_generator: true
  notes: true
  shared_cloud: true
  who_is_home: true
  personal_status: true
  chores: true
  recipes: true
  expiry_tracker: true
  url_shortener: true
  expense_tracker: true
  calendar: true
family_members:
  - Member1
  - Member2
reminders:
  time_format: 24h
  calendar_start_day: monday
  categories:
    - key: health
      label: Health
      color: "#dc2626"
    - key: bills
      label: Bills
      color: "#0d9488"
    - key: family
      label: Family
      color: "#2563eb"
weather:
  enabled: false
theme:
  primary_color: "#1d4ed8"
  secondary_color: "#a0aec0"
  background_color: "#f7fafc"
  card_background_color: "#fff"
  text_color: "#333"
  sidebar_background_color: "#2563eb"
  sidebar_text_color: "#ffffff"
  sidebar_link_color: "rgba(255,255,255,0.95)"
  sidebar_link_border_color: "rgba(255,255,255,0.18)"
  sidebar_active_color: "#3b82f6"
CFGEOF
fi
