.PHONY: all integration_up integration_down generate_config clean_config script_run script_clean splunk_setup
SHELL := /usr/bin/env bash

test_files ?= ./tests/fixtures/integration/docker/
config_file_path ?= config.yaml
db_hostname ?= 127.0.0.1
db_name ?= kong
db_username ?= kong
db_password ?= kong
kong_admin_url ?= http://kong-control-plane:8001
splunk_url ?= http://localhost:9001
kong_admin_token ?= password
update_rate ?= 30
update_type ?= service_retries

kong_version ?= 2.8.1.3-rhel7
kong_image ?= kong/kong-gateway
mem_cache_size ?= 256m
portal_app_auth ?= kong-oauth2
plugins ?= acl,acme,application-registration,aws-lambda,azure-functions,basic-auth,bot-detection,canary,collector,correlation-id,cors,datadog,degraphql,exit-transformer,file-log,forward-proxy,graphql-proxy-cache-advanced,graphql-rate-limiting-advanced,grpc-gateway,grpc-web,hmac-auth,http-log,ip-restriction,jq,jwt,jwt-signer,kafka-log,kafka-upstream,key-auth,key-auth-enc,ldap-auth,ldap-auth-advanced,loggly,mocking,oauth2,oauth2-introspection,opa,openid-connect,post-function,pre-function,prometheus,proxy-cache,proxy-cache-advanced,rate-limiting,rate-limiting-advanced,request-size-limiting,request-termination,request-transformer,request-transformer-advanced,request-validator,response-ratelimiting,response-transformer,response-transformer-advanced,route-by-header,route-transformer-advanced,session,statsd,statsd-advanced,syslog,tcp-log,udp-log,upstream-timeout,vault-auth,zipkin,splunk-hec
log_level ?= debug
db_update_frequency ?= 30s
cluster_max_payload ?= 8388608
cluster_data_plane_purge_delay ?= 259200
portal_gui_access_log ?= /dev/stdout
portal_gui_error_log ?= /dev/stderr
portal_api_access_log ?= /dev/stdout
portal_api_error_log ?= /dev/stderr
admin_gui_access_log ?= /dev/stdout
admin_gui_error_log ?= /dev/stderr
admin_access_log ?= /dev/stdout
admin_error_log ?= /dev/stderr
proxy_access_log ?= /dev/stdout
proxy_error_log ?= /dev/stderr
nginx_worker_processes ?= 8
nginx_worker_processes_dp ?= 4
worker_state_update_frequency ?= 30
worker_consistency ?= eventual
lua_ssl_trusted_certificate ?= system,/etc/secrets/kong-cluster/ca.crt

number_of_workspaces ?= 100
prefix ?= perf
service_protocol ?= https
service_host ?= mockbackend
service_path ?= /
service_port ?= 443

number_of_services ?= 50
number_of_consumers ?= 50
number_of_routes ?= 7

proxy_url= https://haproxy
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

ifndef KONG_LICENSE_DATA
	$(error KONG_LICENSE_DATA is undefined)
endif

export KONG_LOG_LEVEL=$(log_level)
export KONG_VERSION=$(kong_version)
export KONG_IMAGE=$(kong_image)
export KONG_MEMCACHE_SIZE=$(mem_cache_size)
export DB_HOSTNAME=${db_hostname}
export DB_NAME=${db_name}
export DB_USERNAME=${db_username}
export DB_PASSWORD=${db_password}
export KONG_DB_UPDATE_FREQUENCY=${db_update_frequency}
export KONG_CLUSTER_MAX_PAYLOAD=${cluster_max_payload}
export KONG_CLUSTER_DATA_PLANE_PURGE_DELAY=${cluster_data_plane_purge_delay}
export KONG_PORTAL_GUI_ACCESS_LOG=${portal_gui_access_log}
export KONG_PORTAL_GUI_ERROR_LOG=${portal_gui_error_log}
export KONG_PORTAL_API_ACCESS_LOG=${portal_api_access_log}
export KONG_PORTAL_API_ERROR_LOG=${portal_api_error_log}
export KONG_ADMIN_GUI_ACCESS_LOG=${admin_gui_access_log}
export KONG_ADMIN_GUI_ERROR_LOG=${admin_gui_error_log}
export KONG_ADMIN_ACCESS_LOG=${admin_access_log}
export KONG_ADMIN_ERROR_LOG=${admin_error_log}
export KONG_PROXY_ACCESS_LOG=${proxy_access_log}
export KONG_PROXY_ERROR_LOG=${proxy_error_log}
export KONG_NGINX_WORKER_PROCESSES=${nginx_worker_processes}
export KONG_NGINX_WORKER_PROCESSES_DP=${nginx_worker_processes_dp}
export KONG_MEM_CACHE_SIZE=${mem_cache_size}
export KONG_PORTAL_APP_AUTH=${portal_app_auth}
export KONG_PLUGINS=${plugins}
export KONG_WORKER_STATE_UPDATE_FREQUENCY=${worker_state_update_frequency}
export KONG_WORKER_CONSISTENCY=${worker_consistency}
export KONG_LUA_SSL_TRUSTED_CERTIFICATE=${lua_ssl_trusted_certificate}

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
  splunk-hec:
    config:
      keepalive: 60000
      timeout: 10000
      flush_timeout: 2
      http_endpoint: https://splunk:8088/services/collector/event?index=kong
      debug: true
      token: REPLACE_ME
      queue_size: 2000
      headers: {}
      custom_fields_by_lua: {}
      content_type: application/json
      method: POST
      retry_count: 3
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
endef

export CONFIG_FILE

define CONFIG_FILE_PLAIN
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
endef

export CONFIG_FILE_PLAIN

test: generate_config integration_up splunk_setup script_run perf_test
clean: script_clean integration_down clean_config

generate_config:
	echo "$$CONFIG_FILE" > $(CONFIG_FILE_PATH)

generate_config_plain:
	echo "$$CONFIG_FILE_PLAIN" > $(CONFIG_FILE_PATH)

clean_config:
	rm -f $(CONFIG_FILE_PATH)

integration_up:
	@echo "brining up integration environment"; \
	pushd $(test_files); \
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
		-f kong-updater/kong-updater.yml \
		up $${FORCE_RECREATE} -d; \
		docker wait kong-bootstrap; \
	popd;

integration_down:
	@echo "destroying integration environment"; \
	pushd $(test_files); \
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
		-f kong-updater/kong-updater.yml \
		down; \
	popd;


splunk_setup:
	@echo "setting up Splunk"; \
	sleep 30; \
	curl --retry 500 $(splunk_url); 
	docker exec -ti splunk sudo /opt/splunk/bin/splunk list user -auth admin:password;
	docker exec -ti splunk sudo /opt/splunk/bin/splunk add index kong;
	tkn=$$(docker exec -ti splunk sudo /opt/splunk/bin/splunk http-event-collector create perf-token-10 -auth admin:password -uri https://localhost:8089 -description "thisis a new perf token" -index kong | awk -F'=' '/token=/{print $$2}'); \
	sed -i "s/REPLACE_ME/$$tkn/" $(config_file_path);

script_run:
	@echo "running import test"; \
	python ./runner.py \
	--route-dump \
	--route-dump-location $(test_files)/k6/samples/data.json \
	--config-file $$CONFIG_FILE_PATH \
	--hostname $$DB_HOSTNAME \
	--database $$DB_NAME \
	--username $$DB_USERNAME \
  --password $$DB_PASSWORD; \
	docker exec -ti kong-control-plane kong restart || true; \
	sleep 35;

script_clean:
	@echo "running delete test"; \
	python ./runner.py \
	--config-file $$CONFIG_FILE_PATH \
	--hostname $$DB_HOSTNAME \
	--database $$DB_NAME \
	--username $$DB_USERNAME \
  --password $$DB_PASSWORD \
	--delete; \
	docker exec -ti kong-control-plane kong restart || true;


perf_test:
	@echo "running performance test"; \
	pushd $(test_files); \
	docker-compose -f docker-compose.yml \
	-f k6/k6.yml run -v "$$(pwd)/k6/samples:/scripts" k6 run \
	--summary-trend-stats="min,med,avg,max,p(90),p(95),p(99),p(99.9),p(99.99)" \
	--insecure-skip-tls-verify=true \
	-e DATA_FILE=$${DATA_FILE} -e RATE=$${RATE} -e TIME_UNIT=$${TIME_UNIT} \
	-e DURATION=$${DURATION} -e VUS=$${VUS} -e MAX_VUS=$${MAX_VUS} \
	-e PROXY_URL=$${PROXY_URL} $${K6_FILE}; \
	popd;
