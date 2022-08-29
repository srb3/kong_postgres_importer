#!/usr/bin/env bash

topo="${1:-kong_gateway}"
control="${DMODE:-up}"
kong_version="${KONG_VERSION:-2.8.1.1-alpine}"
kong_plugins="${PLUGINS:-bundled}"
kong_config="${DECK_CONFIG}"
admin_url="${ADMIN_URL:-http://localhost:8001}"
token="${TOKEN:-password}"
workspace="${WORKSPACE:-default}"
script="${SCRIPT}"
quiet="${QUIET}"

base_path=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
compose_dir="./compose_topologies"

remove_splunk_file() {
	pushd "${base_path}" || exit
	if [[ -f .splunk_token ]]; then
		echo "removing splunk token"
		rm -f .splunk_token
	fi
}

wait_connect() {
	curl --retry-all-errors --connect-timeout 5 \
		--max-time 10 \
		--retry 5 \
		--retry-delay 0 \
		--retry-max-time 40 \
		"$admin_url" &>>/dev/null
}

deck_sync() {
	wait_connect
	if [[ -d "${base_path}/dumps/$kong_config/workspaces" ]]; then
		pushd "${base_path}/dumps/$kong_config/workspaces" || exit
		for i in $(ls); do
			if [[ -n "${quiet}" ]]; then
				deck sync \
					--kong-addr "$admin_url" \
					--headers "kong-admin-token: $token" \
					-s "$i" &>/dev/null
			else
				deck sync \
					--kong-addr "$admin_url" \
					--headers "kong-admin-token: $token" \
					-s "$i"
			fi
		done
		popd || exit
	else
		deck sync \
			--kong-addr "$admin_url" \
			--headers "kong-admin-token: $token" \
			--workspace "$workspace" \
			-s "${base_path}/dumps/$kong_config/split"
	fi
}

post_script() {
	wait_connect
	pushd "${base_path}" || exit
	if [[ -n "${quiet}" ]]; then
		bash "${base_path}/scripts/${script}/run.sh" &>/dev/null
	else
		bash "${base_path}/scripts/${script}/run.sh"
	fi
	popd || exit
}

up() {
	compose_up
}

down() {
	compose_down
}

compose_up() {
	docker-compose -f docker-compose.yml \
		-f postgres/postgres.yml \
		-f kong-bootstrap/kong-bootstrap.yml \
		-f kong-control-plane/kong-control-plane.yml \
		-f kong-data-plane/kong-data-plane.yml \
		-f pgadmin/pgadmin.yml \
		up -d
}

compose_down() {
	docker-compose -f docker-compose.yml \
		-f postgres/postgres.yml \
		-f kong-bootstrap/kong-bootstrap.yml \
		-f kong-control-plane/kong-control-plane.yml \
		-f kong-data-plane/kong-data-plane.yml \
		-f pgadmin/pgadmin.yml \
		down
}

run() {
	if [[ "$control" == "up" ]]; then
		up
		if [[ -n "$kong_config" ]] && [[ "$topo" != "dbless" ]]; then
			echo "skipping deck_sync"
		fi
		if [[ -n "$script" ]]; then
			post_script
		fi
	elif [[ "$control" == "down" ]]; then
		echo "calling down"
		down
		remove_splunk_file
	elif [[ "$control" == "restart-dbless" ]]; then
		docker-compose -f docker-compose.yml \
			-f kong-dbless/kong-dbless.yml \
			restart kong-dbless
	elif [[ "$control" == "restart-dp-1" ]]; then
		docker-compose restart kong-data-plane-1
	elif [[ "$control" == "restart-dp-2" ]]; then
		docker-compose restart kong-data-plane-2
	elif [[ "$control" == "restart-cp" ]]; then
		docker-compose restart kong-control-plane
	elif [[ "$control" == "restart-kong" ]]; then
		docker-compose restart kong
	elif [[ "$control" == "restart" ]]; then
		echo "restarting"
		down
		up
		if [[ -n "$kong_config" ]] && [[ "$topo" != "dbless" ]]; then
			deck_sync
		fi
		if [[ -n "$script" ]]; then
			post_script
		fi
	fi
}

kong_gateway() {
	local path="${compose_dir}/${topo}"
	export KONG_PLUGINS="$kong_plugins"
	export KONG_VERSION="$kong_version"
	pushd "$path" || exit
	echo "calling run from ${topo}"
	run
	popd || exit
}

echo "CI_MODE IS: ${CI_MODE}"

$topo
