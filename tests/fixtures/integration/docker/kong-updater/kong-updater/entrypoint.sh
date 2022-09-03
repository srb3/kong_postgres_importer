#!/usr/bin/env sh

echo "starting updater"

workspace_name="${PREFIX}-workspace-0"
service_name="${workspace_name}-svc-0"

echo "workspace_name: ${workspace_name}"
echo "service_name: ${service_name}"
echo "UPDATE_TYPE: ${UPDATE_TYPE}"
echo "KONG_ADMIN_URL: ${KONG_ADMIN_URL}"
echo "KONG_ADMIN_TOKEN: ${KONG_ADMIN_TOKEN}"
echo "UPDATE_RATE: ${UPDATE_RATE}"

while true; do
	r=$(shuf -i1-10 -n1)
  echo "random: ${r}"
	if [ "${UPDATE_TYPE}" = "service_retries" ]; then
		curl -s -i -XPATCH -H "kong-admin-token:${KONG_ADMIN_TOKEN}" \
			"${KONG_ADMIN_URL}/${workspace_name}/services/${service_name}" \
			-d "retries=${r}"
	fi
	sleep "${UPDATE_RATE}"
done
