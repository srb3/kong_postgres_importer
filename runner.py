import psycopg
import json
import uuid
import yaml
import re
from typing import Dict, List, Any
from datetime import datetime, timezone


class Runner(object):
    """
    A class used to orchestrate the parsing of config into kong entites,
    and then pass those entities into kong

    Attributes
    ----------
    config_file : string
        a path to a config file containing the types and ammount of
        entity to create
    db_params: dict
        A dictionary of database connection parameters, used for accessing
        the Kong database

    Methods
    -------
    """

    def __init__(
        self,
        config_file=None,
        db_params=None,
        delete=False,
        route_dump=False,
        route_dump_location=None,
        route_prefix=None,
        route_trailing_slash=None,
    ) -> None:
        """
        Parameters
        ----------
        config_file : str
            The Path to the modules config file (YAML)
        db_params: dict
            A dictionary of database connection parameters, used for accessing
            the Kong database
        """
        self.config_file: str = config_file
        self.db_params: Dict[str, str] = db_params
        self.data: Dict[str, Any] = self.parse_config(self.config_file)
        self.prefix: str = self.data["prefix"]
        self.delete: bool = delete
        self.route_dump: bool = route_dump
        self.route_dump_location = route_dump_location or "./routes.josn"
        self.required_workspaces: List[List[str]] = self.gen_workspaces(
            self.data["workspaces"]
        )
        self.required_workspace_names: List[str] = [
            v[1] for v in self.required_workspaces
        ]
        self.route_prefix = route_prefix
        self.route_trailing_slash = route_trailing_slash

        self.number_of_services: int = int(self.data["services_per_workspace"])
        self.number_of_routes: int = int(self.data["routes_per_service"])
        self.number_of_consumers: int = int(self.data["consumers_per_workspace"])
        self.number_of_plugins: int = len(self.data["plugins"]) or 0
        self.plugins = self.data["plugins"] or {}
        self.svc_defaults = self.get_svc_defaults(self.data)

        self.entites: List[str] = [
            "workspaces",
            "services",
            "routes",
            "consumers",
            "plugins",
        ]

        self.get_items: Dict[str, List[str]] = {
            "workspaces": ["name", "id"],
            "services": ["id", "name", "ws_id"],
            "routes": ["id", "name", "service_id", "ws_id"],
            "plugins": ["id", "name", "service_id", "cache_key", "ws_id"],
            "consumers": ["id", "username", "ws_id"],
        }

        self.insert_items: Dict[str, List[str]] = {
            "workspaces": ["id", "name", "meta"],
            "services": [
                "id",
                "name",
                "retries",
                "protocol",
                "host",
                "port",
                "path",
                "connect_timeout",
                "write_timeout",
                "read_timeout",
                "ws_id",
                "enabled",
                "created_at",
                "updated_at",
            ],
            "routes": [
                "id",
                "name",
                "service_id",
                "protocols",
                "paths",
                "regex_priority",
                "strip_path",
                "preserve_host",
                "https_redirect_status_code",
                "path_handling",
                "ws_id",
                "request_buffering",
                "response_buffering",
                "methods",
                "created_at",
                "updated_at",
                "hosts",
            ],
            "plugins": [
                "id",
                "name",
                "service_id",
                "config",
                "enabled",
                "cache_key",
                "protocols",
                "ws_id",
            ],
            "consumers": [
                "id",
                "username",
                "ws_id",
                "username_lower",
                "type",
            ],
        }

        self.get_entity_data: Dict[str, Any] = {
            "workspaces": self.workspaces_parser,
            "services": self.services_parser,
            "routes": self.routes_parser,
            "consumers": self.consumers_parser,
            "plugins": self.plugins_parser,
        }

        self.entity_data_hydrate: Dict[str, Any] = {
            "workspaces": self.workspaces_data_hydrate,
            "services": self.services_data_hydrate,
            "routes": self.routes_data_hydrate,
            "consumers": self.consumers_data_hydrate,
            "plugins": self.plugins_data_hydrate,
        }

        self.db_cache: Dict[str, Any] = {
            "workspaces": {},
            "services": {},
            "routes": {},
            "consumers": {},
            "plugins": {},
        }

        self.parse_cache: Dict[str, Any] = {
            "workspaces": {},
            "services": {},
            "routes": {},
            "consumers": {},
            "plugins": {},
        }

        self.composit_cache: Dict[str, Any] = {
            "workspaces": [],
            "services": [],
            "routes": [],
            "consumers": [],
            "plugins": [],
        }

        self.require_strings: Dict[str, Any] = {
            "workspaces": self.workspaces_require_string,
            "services": self.services_require_string,
            "routes": self.routes_require_string,
            "consumers": self.consumers_require_string,
            "plugins": self.plugins_require_string,
        }
        if self.route_dump:
            print("dumping routes")
            with open(self.route_dump_location, "w") as f:
                json.dump(self.dump_routes(), f)
        if self.delete:
            print("deleting entities")
            self.delete_entities()
        else:
            print("creating entities")
            self.create_entities()

    ################# Data parsers #############################

    def workspaces_require_string(self) -> List[str]:
        return ["{}^{}".format(v[0], v[1]) for v in self.required_workspaces]

    def consumers_require_string(self) -> List[str]:
        return [
            "{}-consumer-{}^{}".format(k, i, v["id"])
            for i in range(self.number_of_consumers)
            for k, v in self.get_active_entities_data("workspaces").items()
        ]

    def services_require_string(self) -> List[str]:
        return [
            "{}-svc-{}^{}".format(k, i, v["id"])
            for i in range(self.number_of_services)
            for k, v in self.get_active_entities_data("workspaces").items()
        ]

    def dump_routes(self) -> List[str]:
        routes = []
        for ws in self.required_workspace_names:
            for s in range(self.number_of_services):
                for r in range(self.number_of_routes):
                    if self.route_prefix:
                        path = "{}/{}-svc-{}-route-{}".format(self.prefix, ws, s, r)
                    else:
                        path = "{}-svc-{}-route-{}".format(ws, s, r)
                    if self.route_trailing_slash:
                        path = path + "/fakeAccounts?count=10&sleep=90"
                    routes.append(path)
        return routes

    def routes_require_string(self) -> List[str]:
        return [
            "{}-route-{}^{}^{}".format(v["name"], i, k, v["ws_id"])
            for i in range(self.number_of_routes)
            for k, v in self.get_active_entities_data("services").items()
        ]

    def plugins_require_string(self) -> List[str]:
        return [
            "{}^{}^{}".format(p, k, v["ws_id"])
            for p in self.plugins
            for k, v in self.get_active_entities_data("services").items()
        ]

    def workspaces_data_hydrate(self, comp: str = ""):
        p = comp.split("^")
        id_ = p[0]
        name = p[1]
        meta = '{"color": "#3894f0"%"thumbnail": null}'
        return "{},{},{}".format(id_, name, meta)

    def services_data_hydrate(self, comp: str):
        p = comp.split("^")
        name = p[0]
        ws_id = p[1]
        created_at = datetime.now(timezone.utc).strftime("%Y-%m-%d %X+00")
        retries = self.svc_defaults["retries"]
        protocol = self.svc_defaults["protocol"]
        host = self.svc_defaults["host"]
        port = self.svc_defaults["port"]
        path = self.svc_defaults["path"]
        connect_timeout = self.svc_defaults["connect_timeout"]
        write_timeout = self.svc_defaults["write_timeout"]
        read_timeout = self.svc_defaults["read_timeout"]
        return "{},{},{},{},{},{},{},{},{},{},{},true,{},{}".format(
            uuid.uuid4(),
            name,
            retries,
            protocol,
            host,
            port,
            path,
            connect_timeout,
            write_timeout,
            read_timeout,
            ws_id,
            created_at,
            created_at,
        )

    def consumers_data_hydrate(self, comp: str):
        p = comp.split("^")
        username = p[0]
        ws_id = p[1]
        username_lower = username
        type_ = "0"
        return "{},{},{},{},{}".format(
            uuid.uuid4(), username, ws_id, username_lower, type_
        )

    def routes_data_hydrate(self, comp: str):
        p = comp.split("^")
        name = p[0]
        service_id = p[1]
        ws_id = p[2]
        created_at = datetime.now(timezone.utc).strftime("%Y-%m-%d %X+00")
        if self.route_prefix:
            path = "/" + self.prefix + "/" + name
        else:
            path = "/" + name
        if self.route_trailing_slash:
            path = path + "/"
        return "{},{},{},{{http% https}},{{{}}},0,true,false,426,v0,{},true,true,{{GET% POST}},{},{},{{}}".format(
            uuid.uuid4(),
            name,
            service_id,
            path,
            ws_id,
            created_at,
            created_at,
        )

    def plugins_data_hydrate(self, comp: str):
        p = comp.split("^")
        name = p[0]
        service_id = p[1]
        ws_id = p[2]
        cache_key = "plugins:{}::{}:::{}".format(name, service_id, ws_id)
        return "{},{},{},CONFIG,true,{},{{grpc%grpcs%http%https}},{}".format(
            uuid.uuid4(),
            name,
            service_id,
            cache_key,
            ws_id,
        )

    def workspaces_parser(
        self,
        current: Dict[str, Any],
        required: List[str],
        entity: str,
    ) -> Dict[str, Any]:
        parsed_data = self.parse_cache[entity]

        if parsed_data:
            return parsed_data
        else:
            self.parse_cache[entity] = {
                k: v for k, v in current.items() if v["name"] in required
            }
            return self.parse_cache[entity]

    def services_parser(
        self, current: Dict[str, Any], active: List[str], entity: str
    ) -> Dict[str, Any]:
        parsed_data = self.parse_cache[entity]
        if parsed_data:
            return parsed_data
        else:
            return {
                v["id"]: {
                    "name": v["name"],
                    "ws_id": v["ws_id"],
                    "composit": "{}^{}".format(v["name"], v["ws_id"]),
                }
                for v in current.values()
                if v["ws_id"] in active
            }

    def routes_parser(
        self, current: Dict[str, Any], active: List[str], entity: str
    ) -> Dict[str, Any]:
        parsed_data = self.parse_cache[entity]
        if parsed_data:
            return parsed_data
        else:
            return {
                v["id"]: {
                    "name": v["name"],
                    "ws_id": v["ws_id"],
                    "composit": "{}^{}^{}".format(
                        v["name"], v["service_id"], v["ws_id"]
                    ),
                }
                for v in current.values()
                if v["ws_id"] in active
            }

    def consumers_parser(
        self, current: Dict[str, Any], active: List[str], entity: str
    ) -> Dict[str, Any]:
        parsed_data = self.parse_cache[entity]
        if parsed_data:
            return parsed_data
        else:
            return {
                v["id"]: {
                    "username": v["username"],
                    "composit": "{}^{}".format(v["username"], v["ws_id"]),
                }
                for v in current.values()
                if v["ws_id"] in active
            }

    def plugins_parser(
        self, current: Dict[str, Any], active: List[str], entity: str
    ) -> Dict[str, Any]:
        parsed_data = self.parse_cache[entity]
        if parsed_data:
            return parsed_data
        else:
            return {
                v["id"]: {
                    "name": v["name"],
                    "composit": "{}^{}^{}".format(
                        v["name"], v["service_id"], v["ws_id"]
                    ),
                }
                for v in current.values()
                if v["ws_id"] in active
            }

    ################### Helper functions #########################

    def parse_config(self, config_file) -> Dict[str, Any]:
        d = {}
        with open(config_file, "r") as stream:
            try:
                d = yaml.safe_load(stream)
            except yaml.YAMLError as exc:
                print(exc)
        return d

    def get_svc_defaults(self, data: Dict[str, str]) -> Dict[str, str]:
        return {
            "protocol": self.set_param("service_protocol", "http", data),
            "host": self.set_param("service_host", "httpbin.org", data),
            "port": self.set_param("service_port", "80", data),
            "path": self.set_param("service_path", "/", data),
            "retries": self.set_param("service_retries", "5", data),
            "connect_timeout": self.set_param("service_connect_timeout", "60000", data),
            "write_timeout": self.set_param("service_write_timeout", "60000", data),
            "read_timeout": self.set_param("service_read_timeout", "60000", data),
        }

    def set_param(self, value: str, default: str, data: Dict[str, str]) -> str:
        return data[value] if value in data.keys() else default

    def db_connect(self, params: Dict[str, str]) -> str:
        hostname = self.set_param("hostname", "127.0.0.1", params)
        database = self.set_param("database", "kong", params)
        username = self.set_param("username", "kong", params)
        password = self.set_param("password", "kong", params)
        return "host={} dbname={} user={} password={}".format(
            hostname, database, username, password
        )

    def items_str(self, items: List[str]) -> str:
        return ", ".join(items)

    def name_gen(self, quantity: int, entity: str) -> List[List[str]]:
        data = []
        for e in range(quantity):
            data.append([str(uuid.uuid4()), "{}-{}-{}".format(self.prefix, entity, e)])
        return data

    def gen_workspaces(self, quantity) -> List[List[str]]:
        return self.name_gen(quantity, "workspace")

    def get_active_entity_ids(self, entity) -> List[str]:
        active: Dict[str, Any] = self.get_active_entities_data(entity)
        if entity == "workspaces":
            ret: List[str] = [v["id"] for v in active.values()]
        else:
            ret: List[str] = [k for k in active.keys()]
        return ret

    def get_active_workspace_ids(self) -> List[str]:
        entity = "workspaces"
        active: Dict[str, Any] = self.get_active_entities_data(entity)
        ret: List[str] = [v["id"] for v in active.values()]
        return ret

    def string_rep(self, line: str, find: str = "%", replace: str = ",") -> str:
        return re.sub(find, replace, line)

    ################# Create functions ###########################

    def get_active_entities_data(self, entity: str) -> Dict[str, Any]:
        current: Dict[str, Any] = self.db_cache[entity]
        if not current:
            current: Dict[str, Any] = self.get_entities(self.get_items[entity], entity)
            self.db_cache[entity] = current

        active_workspaces: Dict[str, Any] = self.db_cache["workspaces"]
        if not active_workspaces:
            active_workspaces: Dict[str, Any] = self.get_entities(
                self.get_items["workspaces"], "workspaces"
            )
            self.db_cache["workspaces"] = active_workspaces
        required_workspace_names: List[str] = self.required_workspace_names
        if entity == "workspaces":
            active: List[str] = required_workspace_names
        else:
            active: List[str] = [
                v["id"]
                for v in active_workspaces.values()
                if v["name"] in required_workspace_names
            ]

        return self.get_entity_data[entity](current, active, entity)

    def get_active_entity_composit_names(
        self, entity: str, key: str = "composit"
    ) -> List[str]:
        comp: List[str] = self.composit_cache[entity]
        if not comp:
            data: Dict[str, Any] = self.parse_cache[entity]
            if not data:
                data: Dict[str, Any] = self.get_active_entities_data(entity)
                self.parse_cache[entity] = data
            comp: List[str] = [v[key] for v in data.values()]
            self.composit_cache[entity] = comp
        return comp

    def entities_to_create(self, entity: str) -> List[List[str]]:
        key: str = "composit"
        active: List[str] = self.get_active_entity_composit_names(entity, key)
        required: List[str] = self.require_strings[entity]()
        ret = []
        for v in required:
            p = v.split("^")
            name = v
            if name in active:
                continue
            config = "CONFIG"
            if p[0] in self.plugins.keys():
                config = json.dumps(self.plugins[p[0]]["config"])
            ret.append(
                [
                    self.string_rep(self.string_rep(d), "CONFIG", config)
                    for d in self.entity_data_hydrate[entity](v).split(",")
                ]
            )
        return ret

    def workspaces_to_create(self) -> List[List[str]]:
        key: str = "name"
        entity: str = "workspaces"
        active: List[str] = self.get_active_entity_composit_names(entity, key)
        required: List[str] = self.require_strings[entity]()
        ret = []
        for v in required:
            p = v.split("^")
            name = p[1]
            if name in active:
                continue
            ret.append(
                [
                    self.string_rep(d)
                    for d in self.entity_data_hydrate[entity](v).split(",")
                ]
            )
        return ret

    def create_entity(self, entity: str) -> None:
        if entity == "workspaces":
            entities_needed: List[List[str]] = self.workspaces_to_create()
        else:
            entities_needed: List[List[str]] = self.entities_to_create(entity)
        self.insert_into_table(entity, self.insert_items[entity], entities_needed)

    ################ Delete functions ##############################

    def delete_entity(self, entity: str) -> None:
        if entity == "workspaces":
            delete: List[str] = self.get_active_workspace_ids()
        else:
            delete: List[str] = self.get_active_entity_ids(entity)
        self.delete_from_table(entity, delete)

    ################ SQL function ################################

    def get_entities(self, items: List[str], table: str) -> Dict[str, Any]:
        data = {}
        with psycopg.connect(self.db_connect(self.db_params)) as conn:
            with conn.cursor() as cursor:
                with cursor.copy(
                    "COPY (SELECT {} FROM {}) TO STDOUT".format(
                        self.items_str(items), table
                    )
                ) as copy:
                    for row in copy.rows():
                        data[row[0]] = dict(zip(items, row))
        return data

    def insert_into_table(
        self, table: str, items: List[str], data: List[List[str]]
    ) -> None:
        print("{} to create: {}".format(table, len(data)))
        with psycopg.connect(self.db_connect(self.db_params)) as conn:
            with conn.cursor() as cursor:
                with cursor.copy(
                    "COPY {} ({}) FROM STDIN".format(table, self.items_str(items))
                ) as copy:
                    for record in data:
                        copy.write_row(record)
        self.db_cache[table] = self.get_entities(self.get_items[table], table)

    def delete_from_table(
        self, table: str, ids_to_delete: List[str], id_key: str = "id"
    ):
        print("{} to delete: {}".format(table, len(ids_to_delete)))
        with psycopg.connect(self.db_connect(self.db_params)) as conn:
            with conn.cursor() as cursor:
                cursor.execute("CREATE TEMP TABLE to_delete (id uuid);")
                with cursor.copy("COPY to_delete (id) FROM STDIN;") as copy:
                    for id_ in ids_to_delete:
                        copy.write_row((id_,))
                cursor.execute(
                    """\
                    DELETE FROM {} WHERE
                       {} IN (SELECT id FROM to_delete);""".format(
                        table, id_key
                    )
                )
        self.db_cache[table] = self.get_entities(self.get_items[table], table)

    ################ entry functions ##############################

    def create_entities(self) -> None:
        for entity in self.entites:
            self.create_entity(entity)

    def delete_entities(self) -> None:
        for entity in reversed(self.entites):
            self.delete_entity(entity)


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Kong DB import tool")
    parser.add_argument(
        "--config-file", metavar="path", required=True, help="the path to config file"
    )
    parser.add_argument(
        "--hostname",
        metavar="host",
        required=True,
        default="127.0.0.1",
        help="the hostname for the Kong database",
    )
    parser.add_argument(
        "--database",
        metavar="database",
        required=True,
        default="kong",
        help="the name of the Kong database",
    )
    parser.add_argument(
        "--username",
        metavar="username",
        required=True,
        default="kong",
        help="the username to access the Kong database",
    )
    parser.add_argument(
        "--password",
        metavar="password",
        required=True,
        default="kong",
        help="the password to access the Kong database",
    )
    parser.add_argument(
        "--delete",
        action="store_true",
        help="instead of creating the entities in the kong database delete \
them if this flag is set",
    )
    parser.add_argument(
        "--route-dump",
        action="store_true",
        help="Dump out a JSON list of all route paths (for automated load test)",
    )
    parser.add_argument(
        "--route-dump-location",
        metavar="path",
        required=False,
        help="Dump out a JSON list of all route paths (for automated load test)",
    )

    parser.add_argument(
        "--route-prefix",
        action="store_true",
        help="Append the prefix to the start of the route",
    )

    parser.add_argument(
        "--route-trailing-slash",
        action="store_true",
        help="Append a trailing slash to the route path",
    )

    args = parser.parse_args()
    params = {
        "hostname": args.hostname,
        "database": args.database,
        "username": args.username,
        "password": args.password,
    }
    Runner(
        args.config_file,
        params,
        args.delete,
        args.route_dump,
        args.route_dump_location,
        args.route_prefix,
        args.route_trailing_slash,
    )
