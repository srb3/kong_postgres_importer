import psycopg
import json
import uuid
import yaml
import re
from typing import Dict, List, Any


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

    def __init__(self, config_file=None, db_params=None, delete=False) -> None:
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
        # Required workspaces are those that have been defined in the user
        # configuration
        # return [ [ "<uuid>", "<prefix>-workspace-<number>" ] ]
        self.required_workspaces: List[List[str]] = self.gen_workspaces(
            self.data["workspaces"]
        )
        self.required_workspace_names: List[str] = [
            v[1] for v in self.required_workspaces
        ]

        self.number_of_services: int = int(self.data["services_per_workspace"])
        self.number_of_routes: int = int(self.data["routes_per_service"])
        self.number_of_consumers: int = int(self.data["consumers_per_workspace"])
        self.number_of_plugins: int = len(self.data["plugins"])
        self.plugins = self.data["plugins"]
        # service config defaults
        self.svc_defaults = self.get_svc_defaults(self.data)

        if self.delete:
            print("deleting entities")
            self.delete_entities()
        else:
            print("creating entities")
            self.create_entities()

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

    def name_gen(self, quantity: int, entity: str) -> List[List[str]]:
        data = []
        for e in range(quantity):
            data.append([str(uuid.uuid4()), "{}-{}-{}".format(self.prefix, entity, e)])
        # return [ [ "<uuid>", "<prefix>-<entitiy_name>-<number>" ] ]
        # e.g workspace
        # return [ [ "699dfe67-0f65-4463-89ae-eb429b61c27a", "perf-workspace-70" ] ]
        return data

    def gen_workspaces(self, quantity) -> List[List[str]]:
        # return [ [ "<uuid>", "<prefix>-workspace-<number>" ] ]
        # return [ [ "699dfe67-0f65-4463-89ae-eb429b61c27a", "perf-workspace-70" ] ]
        return self.name_gen(quantity, "workspace")

    def items_str(self, items: List[str]) -> str:
        return ", ".join(items)

    def get_workspaces(self) -> Dict[str, Any]:
        items = ["name", "id"]
        # return = { ws_name: {"name": <ws_name>, "id": <ws_id>} }
        return self.get_entities(items, "workspaces")

    def get_rbac_roles(self) -> Dict[str, Any]:
        items = ["id", "ws_id"]
        return self.get_entities(items, "rbac_roles")

    def get_rbac_role_endpoints(self) -> Dict[str, Any]:
        items = ["role_id", "workspace"]
        return self.get_entities(items, "rbac_role_endpoints")

    def get_entities(self, items: List[str], table: str) -> Dict[str, Any]:
        data = {}
        with psycopg.connect(self.db_connect({})) as conn:
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

    def create_routes(self) -> None:
        items: List[str] = [
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
        ]
        routes_to_create: List[List[str]] = self.routes_to_create()
        self.insert_into_table("routes", items, routes_to_create)

    def create_consumers(self) -> None:
        items: List[str] = [
            "id",
            "username",
            "ws_id",
            "username_lower",
            "type",
        ]
        consumers_to_create: List[List[str]] = self.consumers_to_create()
        self.insert_into_table("consumers", items, consumers_to_create)

    def create_plugins(self) -> None:
        items: List[str] = [
            "id",
            "name",
            "service_id",
            "config",
            "enabled",
            "cache_key",
            "protocols",
            "ws_id",
        ]
        plugins_to_create: List[List[str]] = self.plugins_to_create()
        self.insert_into_table("plugins", items, plugins_to_create)

    def create_services(self) -> None:
        items: List[str] = [
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
        ]
        services_to_create: List[List[str]] = self.services_to_create()
        self.insert_into_table("services", items, services_to_create)

    def create_rbac_roles(self) -> None:
        # current is { id: { ws_id = 'id' } }
        items: List[str] = ["id", "name", "comment", "is_default", "ws_id"]
        rbac_roles_to_create: List[List[str]] = self.rbac_roles_to_create()
        self.insert_into_table("rbac_roles", items, rbac_roles_to_create)

    def create_rbac_role_endpoints(self) -> None:
        items: List[str] = ["role_id", "workspace", "endpoint", "actions", "negative"]
        endpoints_to_create: List[List[str]] = self.rbac_role_endpoints_to_create()
        self.insert_into_table("rbac_role_endpoints", items, endpoints_to_create)

    def get_requried_svc_names(self) -> List[str]:
        data = []
        # get_active_workspace_ids_and_data =
        # { name: {"name": <ws_name>,"id": <ws_id> } }
        for k, v in self.get_active_workspace_ids_and_data().items():
            for i in range(self.number_of_services):
                data.append("{}-svc-{}^{}".format(k, i, v["id"]))
        # return ["<ws_name>-svc-<svc_number>^<ws_id>"]
        return data

    def get_requried_consumer_names(self) -> List[str]:
        data = []
        # get_active_workspace_ids_and_data =
        # { name: {"name": <ws_name>,"id": <ws_id> } }
        for k, v in self.get_active_workspace_ids_and_data().items():
            for i in range(self.number_of_consumers):
                data.append("{}-consumer-{}^{}".format(k, i, v["id"]))
        # return ["<ws_name>-consumer-<consumer_number>^<ws_id>"]
        return data

    def get_requried_route_names(self) -> List[str]:
        data = []
        # get_active_service_ids_and_data =
        # { svc_id: {
        #  "name": <svc_name>,
        #  "ws_id": <ws_id>,
        #  "svc_id_ws_id": "<svc_id>^<ws_id>",
        #  "svc_name_ws_id": "<svc_name>^<ws_id>"} }
        for k, v in self.get_active_service_ids_and_data().items():
            for i in range(self.number_of_routes):
                data.append("{}-route-{}^{}^{}".format(v["name"], i, k, v["ws_id"]))
        # return ["<svc_name>-route-<route_number>^<svc_id>^<ws_id>"]
        return data

    def get_requried_plugin_names(self) -> List[str]:
        data = []
        # get_active_service_ids_and_data =
        # { svc_id: {
        #  "name": <svc_name>,
        #  "ws_id": <ws_id>,
        #  "svc_id_ws_id": "<svc_id>^<ws_id>",
        #  "svc_name_ws_id": "<svc_name>^<ws_id>"} }
        for k, v in self.get_active_service_ids_and_data().items():
            for p in self.plugins:
                data.append("{}^{}^{}".format(p, k, v["ws_id"]))
        # return ["<plugin_name>^<svc_id>^<ws_id>"]
        return data

    def get_active_service_id_ws_composite(self) -> List[str]:
        # active_svc_data = { svc_id: {
        #  "name": <svc_name>,
        #  "ws_id": <ws_id>,
        #  "svc_id_ws_id": "<svc_id>^<ws_id>",
        #  "svc_name_ws_id": "<svc_name>^<ws_id>"} }
        active_svc_data = self.get_active_service_ids_and_data()
        # return = [ "<svc-name>^<ws_id>" ]
        return [v["svc_id_ws_id"] for v in active_svc_data.values()]

    def get_active_service_name_ws_composite(self) -> List[str]:
        # active_svc_data = { svc_id: {
        #  "name": <svc_name>,
        #  "ws_id": <ws_id>,
        #  "svc_id_ws_id": "<svc_id>^<ws_id>",
        #  "svc_name_ws_id": "<svc_name>^<ws_id>"} }
        active_svc_data: Dict[str, Any] = self.get_active_service_ids_and_data()
        # return = [ "<svc-name>^<ws_id>" ]
        return [v["svc_name_ws_id"] for v in active_svc_data.values()]

    def get_active_consumer_name_ws_composite(self) -> List[str]:
        # active_consumer_data = { consumer_id: {
        #  "id": <consumer_id>,
        #  "username": <consumer_username>,
        #  "ws_id": <ws_id>,
        #  "consumer_id_ws_id": "<svc_id>^<ws_id>",
        #  "consumer_username_ws_id": "<consumer_username>^<ws_id>"} }
        active_consumer_data: Dict[str, Any] = self.get_active_consumer_ids_and_data()
        # return = [ "<consumer-username>^<ws_id>" ]
        return [v["consumer_username_ws_id"] for v in active_consumer_data.values()]

    def get_active_route_name_svc_ws_composite(self) -> List[str]:
        # active_svc_data = { route_id: {
        #  "name": <route_name>,
        #  "service_id": <svc_id>
        #  "ws_id": <ws_id>,
        #  "route_id_svc_id_ws_id": "<route_id>^<svc_id>^<ws_id>",
        #  "route_name_svc_id_ws_id": "<route_name>^<svc_id>^<ws_id>"} }
        active_route_data: Dict[str, Any] = self.get_active_route_ids_and_data()
        # return = [ "<route_name><svc_id>^<ws_id>" ]
        return [v["route_name_svc_id_ws_id"] for v in active_route_data.values()]

    def get_active_plugin_name_svc_ws_composite(self) -> List[str]:
        # active_plugin_data = { plugin_id: {
        #  "name": <plugin_name>,
        #  "service_id": <svc_id>
        #  "ws_id": <ws_id>,
        #  "cache_key": "plugins:<plugin_name>::<service_id>::::<ws_id>",
        #  "plugin_id_svc_id_ws_id": "<plugin_id>^<svc_id>^<ws_id>",
        #  "plugin_name_svc_id_ws_id": "<plugin_name>^<svc_id>^<ws_id>"} }
        #  "plugin_name_svc_name_ws_id": "<plugin_name>^<svc_name>^<ws_id>"} }
        active_plugin_data: Dict[str, Any] = self.get_active_plugin_ids_and_data()
        # return = [ "<plugin_name>-<svc_id>^<ws_id>" ]
        return [v["plugin_name_svc_id_ws_id"] for v in active_plugin_data.values()]

    def get_active_service_names(self) -> List[str]:
        svc_ids_and_data = self.get_active_service_ids_and_data()
        return [v["name"] for v in svc_ids_and_data.values()]

    def get_active_service_ids(self) -> List[str]:
        svc_ids_and_data = self.get_active_service_ids_and_data()
        return [k for k in svc_ids_and_data.keys()]

    def get_active_route_ids(self) -> List[str]:
        route_ids_and_data = self.get_active_route_ids_and_data()
        return [k for k in route_ids_and_data.keys()]

    def get_active_consumer_ids(self) -> List[str]:
        consumer_ids_and_data = self.get_active_consumer_ids_and_data()
        return [k for k in consumer_ids_and_data.keys()]

    def get_active_plugin_ids(self) -> List[str]:
        plugin_ids_and_data = self.get_active_plugin_ids_and_data()
        return [k for k in plugin_ids_and_data.keys()]

    def get_active_service_ids_and_data(self) -> Dict[str, Any]:
        items = ["id", "name", "ws_id"]
        current_services: Dict[str, Any] = self.get_entities(items, "services")
        # ws_data = { name: {"name": <ws_name>,"id": <ws_id> } }
        active_ws_data: Dict[str, Any] = self.get_active_workspace_ids_and_data()
        active_ws_ids: List[str] = [v["id"] for v in active_ws_data.values()]
        # return = { svc_id: {
        #  "name": <svc_name>,
        #  "ws_id": <ws_id>,
        #  "svc_id_ws_id": "<svc_id>^<ws_id>",
        #  "svc_name_ws_id": "<svc_name>^<ws_id>"} }
        return {
            v["id"]: {
                "name": v["name"],
                "ws_id": v["ws_id"],
                "svc_id_ws_id": "{}^{}".format(v["id"], v["ws_id"]),
                "svc_name_ws_id": "{}^{}".format(v["name"], v["ws_id"]),
            }
            for v in current_services.values()
            if v["ws_id"] in active_ws_ids
        }

    def get_active_consumer_ids_and_data(self) -> Dict[str, Any]:
        items = ["id", "username", "ws_id"]
        current_consumers: Dict[str, Any] = self.get_entities(items, "consumers")
        # ws_data = { name: {"name": <ws_name>,"id": <ws_id> } }
        active_ws_data: Dict[str, Any] = self.get_active_workspace_ids_and_data()
        active_ws_ids: List[str] = [v["id"] for v in active_ws_data.values()]
        # return = { consumer_id: {
        #  "id": <consumer_id>
        #  "username": <consumer_username>,
        #  "ws_id": <ws_id>,
        #  "consumer_id_ws_id": "<consumer_id>^<ws_id>",
        #  "consumer_username_ws_id": "<consumer_username>^<ws_id>"} }
        return {
            v["id"]: {
                "username": v["username"],
                "id": v["id"],
                "ws_id": v["ws_id"],
                "consumer_id_ws_id": "{}^{}".format(v["id"], v["ws_id"]),
                "consumer_username_ws_id": "{}^{}".format(v["username"], v["ws_id"]),
            }
            for v in current_consumers.values()
            if v["ws_id"] in active_ws_ids
        }

    def get_active_route_ids_and_data(self) -> Dict[str, Any]:
        items = ["id", "name", "service_id", "ws_id"]
        current_routes: Dict[str, Any] = self.get_entities(items, "routes")
        # ws_data = { name: {"name": <ws_name>,"id": <ws_id> } }
        active_ws_data: Dict[str, Any] = self.get_active_workspace_ids_and_data()
        active_ws_ids: List[str] = [v["id"] for v in active_ws_data.values()]
        # return = { svc_id: {
        #  "name": <svc_name>,
        #  "ws_id": <ws_id>,
        #  "svc_id_ws_id": "<svc_id>^<ws_id>",
        #  "svc_name_ws_id": "<svc_name>^<ws_id>"} }
        return {
            v["id"]: {
                "name": v["name"],
                "ws_id": v["ws_id"],
                "service_id": v["service_id"],
                "route_id_svc_id_ws_id": "{}^{}^{}".format(
                    v["id"], v["service_id"], v["ws_id"]
                ),
                "route_name_svc_id_ws_id": "{}^{}^{}".format(
                    v["name"], v["service_id"], v["ws_id"]
                ),
            }
            for v in current_routes.values()
            if v["ws_id"] in active_ws_ids
        }

    def get_active_plugin_ids_and_data(self) -> Dict[str, Any]:
        items = ["id", "name", "service_id", "cache_key", "ws_id"]
        current_plugins: Dict[str, Any] = self.get_entities(items, "plugins")
        # ws_data = { name: {"name": <ws_name>,"id": <ws_id> } }
        active_ws_data: Dict[str, Any] = self.get_active_workspace_ids_and_data()
        active_ws_ids: List[str] = [v["id"] for v in active_ws_data.values()]
        # return = { plugin_id: {
        #  "name": <plugin_name>,
        #  "service_id": <service_id>,
        #  "ws_id": <ws_id>,
        #  "cache_key": "plugins:<plugin_name>::<service_id>::::<ws_id>",
        #  "plugin_id_svc_id_ws_id": "<plugin_id>^<svc_id>^<ws_id>",
        #  "plugin_name_svc_id_ws_id": "<plugin_name>^<svc_id>^<ws_id>"} }
        return {
            v["id"]: {
                "name": v["name"],
                "service_id": v["service_id"],
                "ws_id": v["ws_id"],
                "cache_key": v["cache_key"],
                "plugin_id_svc_id_ws_id": "{}^{}^{}".format(
                    v["id"], v["service_id"], v["ws_id"]
                ),
                "plugin_name_svc_id_ws_id": "{}^{}^{}".format(
                    v["name"], v["service_id"], v["ws_id"]
                ),
            }
            for v in current_plugins.values()
            if v["ws_id"] in active_ws_ids
        }

    def get_active_rbac_role_endpoint_ids(self) -> List[str]:
        items = ["role_id", "workspace"]
        current_rbac_roles_endpoints: Dict[str, Any] = self.get_entities(
            items, "rbac_role_endpoints"
        )
        active_ws_names: List[str] = self.get_active_workspace_names()
        return [
            v["role_id"]
            for v in current_rbac_roles_endpoints.values()
            if v["workspace"] in active_ws_names
        ]

    def get_active_rbac_role_ids(self) -> List[str]:
        items = ["id", "ws_id"]
        current_rbac_roles: Dict[str, Any] = self.get_entities(items, "rbac_roles")
        active_ws_ids: List[str] = self.get_active_workspace_ids()
        return [
            v["id"] for v in current_rbac_roles.values() if v["ws_id"] in active_ws_ids
        ]

    def get_active_rbac_role_ws_ids_and_data(self) -> Dict[str, Any]:
        items = ["id", "ws_id"]
        current_rbac_roles: Dict[str, Any] = self.get_entities(items, "rbac_roles")
        active_ws_ids: List[str] = self.get_active_workspace_ids()
        # return = { <ws_id>: <role_id> }
        return {
            v["ws_id"]: v["id"]
            for v in current_rbac_roles.values()
            if v["ws_id"] in active_ws_ids
        }

    def get_active_workspace_names(self) -> List[str]:
        # current_active_ws = { id: {"name": <ws_name>,"id": <ws_id> } }
        current_active_ws = self.get_active_workspace_ids_and_data()
        # return = [ "<workspace_name>" ]
        return [v["name"] for v in current_active_ws.values()]

    def get_active_workspace_ids(self) -> List[str]:
        # current_active_ws = { id: {"name": <ws_name>,"id": <ws_id> } }
        current_active_ws = self.get_active_workspace_ids_and_data()
        # return = [ "<workspace_id>" ]
        return [v["id"] for v in current_active_ws.values()]

    def get_active_workspace_ids_and_data(self) -> Dict[str, Any]:
        items = ["name", "id"]
        # ws_current = { ws_name: {"name": <ws_name>, "id": <ws_id>} }
        ws_current: Dict[str, Any] = self.get_entities(items, "workspaces")

        # Returns the workspace data for all the desired workspaces that are
        # present in the Kong database. This data is used to build other entities
        # in the desired worspaces.
        # return { name: {"name": <ws_name>,"id": <ws_id> } }
        return {
            k: v
            for k, v in ws_current.items()
            if v["name"] in self.required_workspace_names
        }

    def create_workspaces(self) -> None:
        # ws_needed = [
        # [ "<uuid>",
        #   "<prefix>-workspace-<number>",
        #   '{"color": "#3894f0","thumbnail": null}']]
        ws_needed: List[List[str]] = self.workspaces_to_create()
        self.insert_into_table("workspaces", ["id", "name", "meta"], ws_needed)
        # active: Dict[str, Any] = self.get_active_workspace_ids_and_data(data)

    def delete_plugins(self) -> None:
        # plugins_to_delete = [<id>]
        plugins_to_delete: List[str] = self.get_active_plugin_ids()
        self.delete_from_table("plugins", plugins_to_delete)

    def delete_consumers(self) -> None:
        # consumers_to_delete = [<id>]
        consumers_to_delete: List[str] = self.get_active_consumer_ids()
        self.delete_from_table("consumers", consumers_to_delete)

    def delete_routes(self) -> None:
        # routes_to_delete = [<id>]
        routes_to_delete: List[str] = self.get_active_route_ids()
        self.delete_from_table("routes", routes_to_delete)

    def delete_services(self) -> None:
        # services_to_delete = [<id>]
        services_to_delete: List[str] = self.get_active_service_ids()
        self.delete_from_table("services", services_to_delete)

    def delete_rbac_role_endpoints(self) -> None:
        # endpoints_to_delete = [<id>]
        endpoints_to_delete: List[str] = self.get_active_rbac_role_endpoint_ids()
        self.delete_from_table("rbac_role_endpoints", endpoints_to_delete, "role_id")

    def delete_rbac_roles(self) -> None:
        # roles_to_delete = [<id>]
        roles_to_delete: List[str] = self.get_active_rbac_role_ids()
        self.delete_from_table("rbac_roles", roles_to_delete)

    def delete_workspaces(self) -> None:
        workspaces_to_delete: List[str] = self.get_active_workspace_ids()
        self.delete_from_table("workspaces", workspaces_to_delete)

    def diff_lists(self, current: List[str], desired: List[str]) -> List[str]:
        return list(set(desired) - set(current))

    def workspaces_to_delete(
        self, current: Dict[str, Any], desired: List[List[str]]
    ) -> List[str]:
        d = ["{}".format(v[1]) for v in desired]
        return [v["id"] for k, v in current.items() if k in d]

    def service_data(self, comp: str):
        p = comp.split("^")
        name = p[0]
        ws_id = p[1]
        retries = self.svc_defaults["retries"]
        protocol = self.svc_defaults["protocol"]
        host = self.svc_defaults["host"]
        port = self.svc_defaults["port"]
        path = self.svc_defaults["path"]
        connect_timeout = self.svc_defaults["connect_timeout"]
        write_timeout = self.svc_defaults["write_timeout"]
        read_timeout = self.svc_defaults["read_timeout"]
        return "{},{},{},{},{},{},{},{},{},{},{},true".format(
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
        )

    def consumer_data(self, comp: str):
        p = comp.split("^")
        username = p[0]
        ws_id = p[1]
        username_lower = username
        type_ = "0"
        return "{},{},{},{},{}".format(
            uuid.uuid4(), username, ws_id, username_lower, type_
        )

    def route_data(self, comp: str):
        p = comp.split("^")
        name = p[0]
        service_id = p[1]
        ws_id = p[2]
        return (
            "{},{},{},{{http% https}},{{/{}}},0,true,false,426,v0,{},true,true".format(
                uuid.uuid4(),
                name,
                service_id,
                name,
                ws_id,
            )
        )

    def plugin_data(self, comp: str):
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

    def services_to_create(self) -> List[List[str]]:
        active_svc_ws: List[str] = self.get_active_service_name_ws_composite()
        required_svc_ws: List[str] = self.get_requried_svc_names()
        return [
            self.service_data(v).split(",")
            for v in required_svc_ws
            if v not in active_svc_ws
        ]

    def routes_to_create(self) -> List[List[str]]:
        active_routes_ws: List[str] = self.get_active_route_name_svc_ws_composite()
        required_route_ws: List[str] = self.get_requried_route_names()
        route_items: List[List[str]] = []
        for v in required_route_ws:
            if v in active_routes_ws:
                continue
            x = self.route_data(v).split(",")
            z = [re.sub("%", ",", y) for y in x]
            route_items.append(z)
        return route_items

    def plugins_to_create(self) -> List[List[str]]:
        active_plugin_ws: List[str] = self.get_active_plugin_name_svc_ws_composite()
        required_plugin_ws: List[str] = self.get_requried_plugin_names()
        plugin_items: List[List[str]] = []
        for v in required_plugin_ws:
            if v in active_plugin_ws:
                continue
            x = self.plugin_data(v).split(",")
            x = [re.sub("%", ",", y) for y in x]
            p = v.split("^")
            config = json.dumps(self.plugins[p[0]]["config"])
            x = [re.sub("CONFIG", config, y) for y in x]
            plugin_items.append(x)
        return plugin_items

    def consumers_to_create(self) -> List[List[str]]:
        active_consumer_ws: List[str] = self.get_active_consumer_name_ws_composite()
        required_consumer_ws: List[str] = self.get_requried_consumer_names()
        return [
            self.consumer_data(v).split(",")
            for v in required_consumer_ws
            if v not in active_consumer_ws
        ]

    def workspaces_to_create(self) -> List[List[str]]:
        # ws_current all the workspaces in Kong DB
        # ws_current = { ws_name: {"name": <ws_name>, "id": <ws_id>} }
        # required_workspaces [ [ "<uuid>", "<prefix>-workspace-<number>" ] ]

        ws_current: Dict[str, Any] = self.get_workspaces()
        current_workspace_names = [v["name"] for v in ws_current.values()]
        # raw is a list of all workspace name that are not currently in the database
        raw = [
            v for v in self.required_workspaces if v[1] not in current_workspace_names
        ]
        # meta is aditional workspace information we might need
        meta = '{"color": "#3894f0","thumbnail": null}'
        # append the meta var to each workspace in the list
        for v in raw:
            v.append(meta)
        # return  = [
        # [ "<uuid>",
        #   "<prefix>-workspace-<number>",
        #   '{"color": "#3894f0","thumbnail": null}']]
        return raw

    def rbac_role_endpoints_to_create(self) -> List[List[str]]:
        # current_role_endpoints =
        # { role_id: { "workspace": <workspace_name>, "role_id": <id> } }
        # e.g.
        # {'e7f90065-08c4-406a-9b11-5d7832f16171': {
        #   'role_id': 'e7f90065-08c4-406a-9b11-5d7832f16171',
        #   'workspace': '*'}
        current_role_endpoints: Dict[str, Any] = self.get_rbac_role_endpoints()
        # current_ws_names_with_role_endpoints = [ <ws_name> ]
        current_ws_names_with_role_endpoints: List[str] = [
            v["workspace"] for v in current_role_endpoints.values()
        ]
        # active_ws_ids_and_data = { name: {"name": <ws_name>,"id": <ws_id> } }
        active_ws_data: Dict[str, Any] = self.get_active_workspace_ids_and_data()

        # desired_ws_names_without_role_endpoints is a list of all the user
        # defined (desired) workspace names that do not have an rbac role endpoint
        # created for them.
        # desired_ws_ids_without_role_endpoints = {'name': '<ws_name>', 'id': '<ws_id>'}]
        desired_ws_data_without_role_endpoints: List[Dict[str, Any]] = [
            v
            for v in active_ws_data.values()
            if v["name"] not in current_ws_names_with_role_endpoints
        ]

        endpoint: str = "*"
        actions: str = "15"
        negative: str = "false"
        active_rbac_roles_by_ws_id = self.get_active_rbac_role_ws_ids_and_data()
        role_endpoints_to_create: List[List[str]] = [
            [
                active_rbac_roles_by_ws_id[v["id"]],
                v["name"],
                endpoint,
                actions,
                negative,
            ]
            for v in desired_ws_data_without_role_endpoints
        ]
        #
        # role_endpoints_to_create =  [
        #   'id',
        #   '<workspace_name>',
        #   '<endpoint>',
        #   '<actions>',
        #   '<negative>']]
        return role_endpoints_to_create

    def rbac_roles_to_create(self) -> List[List[str]]:
        # current_roles = { <id>: { "ws_id": <ws_id>, "id": <id> } }
        # e.g.
        # {'e7f90065-08c4-406a-9b11-5d7832f16171': {
        #   'id': 'e7f90065-08c4-406a-9b11-5d7832f16171',
        #   'ws_id': '73182b10-8b99-4040-8315-88a7fdbb5e30'}}
        current_roles: Dict[str, Any] = self.get_rbac_roles()
        # current_ws_ids_with_roles = [ <ws_id> ]
        current_ws_ids_with_roles: List[str] = [
            v["ws_id"] for v in current_roles.values()
        ]
        # active_ws_ids = { name: {"name": <ws_name>,"id": <ws_id> } }
        active_ws_ids: Dict[str, Any] = self.get_active_workspace_ids_and_data()

        # desired_ws_ids_without_roles is a list of all the user defined (desired)
        # workspace ids that do not have an rbac role created for them
        # desired_ws_ids_without_roles = {'name': '<ws_name>', 'id': '<ws_id>'}]
        desired_ws_ids_without_roles: List[Dict[str, Any]] = [
            v
            for v in active_ws_ids.values()
            if v["id"] not in current_ws_ids_with_roles
        ]

        name: str = "workspace-super-admin"
        comment: str = "Full access to all endpoints in the {} workspace"
        roles_to_create: List[List[str]] = [
            [str(uuid.uuid4()), name, comment.format(v["name"]), "false", v["id"]]
            for v in desired_ws_ids_without_roles
        ]
        # roles_to_create =  [
        #   'id',
        #   'workspace-super-admin',
        #   'Full access to all endpoints in the <workspace_name> workspace',
        #   'false',
        #   'ws_id']]
        return roles_to_create

    def create_entities(self) -> None:
        self.create_workspaces()
        self.create_rbac_roles()
        self.create_rbac_role_endpoints()
        self.create_services()
        self.create_routes()
        self.create_consumers()
        self.create_plugins()

    def delete_entities(self) -> None:
        self.delete_plugins()
        self.delete_consumers()
        self.delete_routes()
        self.delete_services()
        self.delete_rbac_role_endpoints()
        self.delete_rbac_roles()
        self.delete_workspaces()


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

    args = parser.parse_args()
    params = {
        "hostname": args.hostname,
        "database": args.database,
        "username": args.username,
        "password": args.password,
    }
    Runner(args.config_file, params, args.delete)
