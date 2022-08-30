#!/usr/bin/env sh

workspace_name="${PREFIX}-workspace-0"
service_name="${workspace_name}-svc-0"

while true; do
	r=$(shuf -i1-10 -n1)
	if [ "${UPDATE_TYPE}" = "service_retries" ]; then
		curl -s -i -XPATCH -H "kong-admin-token:${KONG_ADMIN_TOKEN}" \
			"${KONG_ADMIN_URL}/${workspace_name}/services/${service_name}" \
			-d "retries=${r}"
	fi
	sleep "${UPDATE_RATE}"
done
