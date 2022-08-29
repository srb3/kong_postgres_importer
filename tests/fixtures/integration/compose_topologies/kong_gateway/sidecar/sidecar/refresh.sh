#!/bin/sh

# set the target for the config POST
# and the status endpoint
KONG_YAML="/kong_dbless/kong.yaml"

ADMIN_SCHEME="${ADMIN_SCHEME:-http}"
ADMIN_HOST="${ADMIN_HOST:-localhost}"
ADMIN_PORT="${ADMIN_PORT:-8001}"

STATUS_HOST="${STATUS_HOST:-localhost}"
STATUS_PORT="${STATUS_PORT:-8100}"
STATUS_SCHEME="${STATUS_SCHEME:-http}"

ADMIN_URL="${ADMIN_SCHEME}://${ADMIN_HOST}:${ADMIN_PORT}/config"
STATUS_URL="${STATUS_SCHEME}://${STATUS_HOST}:${STATUS_PORT}/status"

refresh_kong_config() {
	echo "Sending initial config to Kong"
	curl -i -X POST "${ADMIN_URL}" \
		--data-binary "@${KONG_YAML}"
}

echo "waiting for Kong to become ready"
curl --retry 100 -f --retry-all-errors --retry-delay 5 -s -o /dev/null "${STATUS_URL}"
echo "Kong ready for connections"
refresh_kong_config

while true; do
	if [ -f "${KONG_YAML}" ]; then
		inotifywait ${KONG_YAML} -e DELETE_SELF
		echo "[$(date +%s)] DBless config change detected triggering refresh"
		refresh_kong_config
	else
		sleep 1
	fi
done
