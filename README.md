# Kong database importer

## Summary

This tool was created to help speed up load testing Kong deployments. When
load testing very large deployments it can take a while to create all of the
entities in via Deck or the Kong admin API. This tool will directly create
Kong entities in the Kong database. It only supports Kong deployments 
with a postgresql database.

### Disclaimer

This is tool is a prototype and is not supported by anyone. Use at your own
risk. Bypassing the Kong admin APIs and directly importing data into the
Kong database is a fragile process and is prone to breaking between releases,
and causing unpredictable behaviour.

## Installation

1. clone this repo or extract the zip containing the repo
2. install required modules using pip (see requirements.txt) 
   `pip install -r requirements.txt`
3. create a config file (YAML format) that describes how many entities to
   create in the Kong database. See the Config File section for details
3. run the application (see the Running the Script section)

## Running the Script

Create example:
```
  python ./runner.py \
	--config-file ./config.yaml \
	--hostname 127.0.0.1 \
	--database kong \
	--username kong \
  --password p@55word
```

When run with the above options, the tooling will read and process the config
file (config.yaml). Then it will connect to the database and start creating
entities directly via the [psycopg](https://www.psycopg.org/) library.
The tooling makes use of this of the bulk `COPY` import method to make the
process as efficient as possible.

Delete example:
```
  python ./runner.py \
	--config-file ./config.yaml \
	--hostname 127.0.0.1 \
	--database kong \
	--username kong \
  --password p@55word \
  --delete
```

The `--delete` flag can be passed on the command line and the tooling will
then remove any entities described in the config file from the Kong database


## Config File

The config file should be in YAML format, an example of the config file with
all options specifed is shown below.

```yaml
workspaces: 100
prefix: perf
consumers_per_workspace: 50
services_per_workspace: 50
service_protocol: http
service_host: httpbin.org
service_port: 80
service_path: /
routes_per_service: 7
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

```

As you can see the number of workspaces is dictated by the `workspaces` field.
The workspaces are named with the `prefix-<number>` notaition. so with 100
workspaces specifed and a prefix of perf, you will end up with workspaces 
named `perf-workspace-0` to `perf-workspace-99`. `consumers`, `services` and
`routes` are all declared using a number. Setting `services_per_workspace`
to 50 will create 50 services per workspace, with the name of the service formed
from the workspace and the iteration number of the particular service
e.g. `perf-workspace-37-svc-15`. Routes are created per service do a `routes_per_service`
setting of 7 will create 7 routes for every service in every workspace.
Consumers are created on a workspace level, setting `consumers_per_workspace` to
50 will create 50 consumer in every workspace created by this tool. Consumers are
named as follows: `perf-workspace-39-consumer-43` for the 43rd consumer in the 39th
workspace. Lastly there is plugins, Plugins differ in that there configuration
properties differ wildly, and also teams want flexibility when load testing with
regrads to the plugins they want to load test with. With this in mind the plugins
config is a hash, with the plugin name as the key and then a config key is nested
under the plugin name key. Under the config key you should put all of the configuration
for that particular plugin - even the default or null values. The plugins in the hash
will be applied to every service.
