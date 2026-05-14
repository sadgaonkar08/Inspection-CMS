#!/bin/bash
set -e

echo "[azure-startup] Running rails db:prepare..."
cd /rails
su -s /bin/bash rails -c 'bundle exec rails db:prepare'
echo "[azure-startup] db:prepare complete."

echo "[azure-startup] Starting supervisord..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
