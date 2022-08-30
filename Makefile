.PHONY: all integration_up integration_down generate_config clean_config script_run script_clean
SHELL := /usr/bin/env bash

config_file_path ?= config.yaml
db_hostname ?= 127.0.0.1
db_name ?= kong
db_username ?= kong
db_password ?= kong
kong_admin_url ?= http://localhost:8001
kong_admin_token ?= password
update_rate ?= 30
update_type ?= service_retries

kong_version ?= 2.8.1.3-rhel7
kong_image ?= kong/kong-gateway
mem_cache_size ?= 256m
portal_app_auth ?= kong-oauth2
plugins ?= bundled
log_level ?= debug

number_of_workspaces ?= 100
prefix ?= perf
service_protocol ?= http
service_host ?= mockbackend
service_path ?= /
service_port ?= 80

number_of_services ?= 50
number_of_consumers ?= 50
number_of_routes ?= 7

proxy_url= http://haproxy:80
k6_data_file ?= /scripts/data.json
k6_script_file ?= /scripts/main.js
vus ?= 50
max_vus ?= 900
rate ?=2000
time_unit ?= 1s
duration ?= 60s

ifdef FORCE
	export FORCE_RECREATE=--force-recreate --build -V --no-deps
endif

export KONG_LOG_LEVEL=$(log_level)
export KONG_VERSION=$(kong_version)
export KONG_IMAGE=$(kong_image)
export KONG_MEMCACHE_SIZE=$(mem_cache_size)
export DB_HOSTNAME=${db_hostname}
export DB_NAME=${db_name}
export DB_USERNAME=${db_username}
export DB_PASSWORD=${db_password}

export KONG_MEM_CACHE_SIZE=${mem_cache_size}
export KONG_PORTAL_APP_AUTH=${portal_app_auth}
export KONG_PLUGINS=${plugins}

export CONFIG_FILE_PATH = ${config_file_path}

export KONG_ADMIN_URL = ${kong_admin_url}
export KONG_ADMIN_TOKEN = ${kong_admin_token}
export UPDATE_RATE = ${update_rate}
export UPDATE_TYPE = ${update_type}

export PROXY_URL = ${proxy_url} 
export K6_FILE = ${k6_script_file} 
export DATA_FILE = ${k6_data_file} 
export VUS = ${vus}
export MAX_VUS = ${max_vus}
export RATE = ${rate}
export TIME_UNIT = ${time_unit}
export DURATION = ${duration}


define CONFIG_FILE 
workspaces: $(number_of_workspaces)
prefix: $(prefix)
consumers_per_workspace: $(number_of_consumers)
services_per_workspace: $(number_of_services)
service_protocol: $(service_protocol)
service_host: $(service_host)
service_port: $(service_port)
service_path: $(service_path)
routes_per_service: $(number_of_routes)
plugins:
  file-log:
    config:
      path: "/dev/null"
      custom_fields_by_lua: {}
      reopen: false
  cors:
    config:
      max_age: null
      credentials: false
      exposed_headers: null
      methods: [ "GET" ]
      headers: null
      preflight_continue: false
      origins: [ "*" ]
  ip-restriction:
    config:
      message: null
      allow: null
      deny: [ "1.1.1.1" ]
      status: null
  udp-log:
    config:
      timeout: 0
      port: 9999
      host: "127.0.0.1"
      custom_fields_by_lua: {}
endef

export CONFIG_FILE

test: generate_config integration_up script_run
clean: script_clean integration_down clean_config

generate_config:
	echo "$$CONFIG_FILE" > $(CONFIG_FILE_PATH)

clean_config:
	rm -f $(CONFIG_FILE_PATH)

integration_up:
	@echo "brining up integration environment"; \
	pushd ./tests/fixtures/integration/; \
	docker-compose -f docker-compose.yml \
		-f postgres/postgres.yml \
		-f kong-bootstrap/kong-bootstrap.yml \
		-f kong-control-plane/kong-control-plane.yml \
		-f kong-data-plane/kong-data-plane.yml \
		-f mockbackend/mockbackend.yml \
		-f haproxy/haproxy.yml \
		-f grafana/grafana.yml \
		-f influxdb/influxdb.yml \
		-f k6/k6.yml \
		-f splunk/splunk.yml \
		up $${FORCE_RECREATE} -d; \
		docker wait kong-bootstrap; \
	popd;

integration_down:
	@echo "destroying integration environment"; \
	pushd ./tests/fixtures/integration/; \
	docker-compose -f docker-compose.yml \
		-f postgres/postgres.yml \
		-f kong-bootstrap/kong-bootstrap.yml \
		-f kong-control-plane/kong-control-plane.yml \
		-f kong-data-plane/kong-data-plane.yml \
		-f mockbackend/mockbackend.yml \
		-f haproxy/haproxy.yml \
		-f grafana/grafana.yml \
		-f influxdb/influxdb.yml \
		-f k6/k6.yml \
		-f splunk/splunk.yml \
		down; \
	popd;

script_run:
	@echo "running import test"; \
	python ./runner.py \
	--route-dump \
	--route-dump-location tests/fixtures/integration/k6/samples/data.json \
	--config-file $$CONFIG_FILE_PATH \
	--hostname $$DB_HOSTNAME \
	--database $$DB_NAME \
	--username $$DB_USERNAME \
  --password $$DB_PASSWORD;


script_clean:
	@echo "running delete test"; \
	python ./runner.py \
	--config-file $$CONFIG_FILE_PATH \
	--hostname $$DB_HOSTNAME \
	--database $$DB_NAME \
	--username $$DB_USERNAME \
  --password $$DB_PASSWORD \
	--delete;

kong_updater:
	@echo "running kong kong updater"; \
	pushd ./tests/fixtures/integration/; \
	docker-compose -f docker-compose.yml \
	-f kong-updater/kong-updater.yml \
	-e KONG_ADMIN_URL=$${KONG_ADMIN_URL} -e UPDATE_RATE=$${UPDATE_RATE} \
	-e UPDATE_TYPE=$${UPDATE_TYPE} -e KONG_ADMIN_TOKEN=$${KONG_ADMIN_TOKEN} \
	-e PREFIX=$${PREFIX} \
	up -d \
	popd;

perf_test:
	@echo "running performance test"; \
	pushd ./tests/fixtures/integration/; \
	docker-compose -f docker-compose.yml \
	-f k6/k6.yml run -v "$$(pwd)/k6/samples:/scripts" k6 run \
	--summary-trend-stats="min,med,avg,max,p(90),p(95),p(99),p(99.9),p(99.99)" \
	-e DATA_FILE=$${DATA_FILE} -e RATE=$${RATE} -e TIME_UNIT=$${TIME_UNIT} \
	-e DURATION=$${DURATION} -e VUS=$${VUS} -e MAX_VUS=$${MAX_VUS} \
	-e PROXY_URL=$${PROXY_URL} $${K6_FILE}; \
	popd;
