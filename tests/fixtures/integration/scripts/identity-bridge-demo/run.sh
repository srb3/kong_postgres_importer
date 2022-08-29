#!/usr/bin/env bash
KONG_ADMIN_URL=http://localhost:8001
TOKEN=password
#set -x
source ./terraform/azure-ad/temp_files/idp_creds_env

#echo "$CLIENT_ID"
#echo "$CLIENT_SECRET"
#echo "$TENANT_ID"

# create default super admin role
workspace="default"
curl -s -k -X POST -H "kong-admin-token:${TOKEN}" \
	"${KONG_ADMIN_URL}/${workspace}/rbac/roles/" \
	--data 'name=super-admin' \
	--data "comment=${workspace} super admin"

# create admin permisions
curl -k -X POST -H "kong-admin-token:${TOKEN}" \
	"${KONG_ADMIN_URL}/${workspace}/rbac/roles/super-admin/endpoints" \
	--data "workspace=${workspace}" \
	--data 'endpoint=*' \
	--data 'actions=delete,update,read,create' \
	--data 'negative=false'

# create admin group
curl -i -s -k -X POST "${KONG_ADMIN_URL}/${workspace}/groups" \
	--data "comment=${workspace} Admin Group" \
	--data "name=${workspace}-admin" \
	-H "kong-admin-token: ${TOKEN}"
echo -e "\n"

# get workspace super admin role id
admin_role_id=$(curl -s -k "${KONG_ADMIN_URL}/${workspace}/rbac/roles/super-admin" \
	-H "Kong-Admin-Token: ${TOKEN}" | jq -r '.id')

# get workspace id
workspace_id=$(curl -s -k "${KONG_ADMIN_URL}/workspaces/${workspace}" \
	-H "Kong-Admin-Token: ${TOKEN}" | jq -r '.id')

# assign super admin group to role and workspace
curl -i -s -k -X POST "${KONG_ADMIN_URL}/groups/${workspace}-admin/roles" \
	-H "Kong-Admin-Token: ${TOKEN}" \
	--data "rbac_role_id=${admin_role_id}" \
	--data "workspace_id=${workspace_id}"
echo -e "\n"

# register manager users
email="hsbc-admin-local@stephenb583gmail@onmicrosoft.com"
name="hsbc-admin"
curl -s -k -X POST "${KONG_ADMIN_URL}/${workspace}/admins" \
	-H "Kong-Admin-Token:${TOKEN}" \
	-H "Content-Type: application/json" \
	-d "{\"email\":\"${email}\",\"username\":\"${name}\",\"custom_id\":\"${name}\",\"rbac_token_enabled\":true}"
echo -e "\n"

# create migration super admin role
workspace="default"
curl -s -k -X POST -H "kong-admin-token:${TOKEN}" \
	"${KONG_ADMIN_URL}/${workspace}/rbac/roles/" \
	--data 'name=migration-super-admin' \
	--data "comment=${workspace} migration super admin"

declare -a endpoints=(
	"developers/" "developers/*" "plugins/" "plugins/*" "acls/" "acls/*"
	"applications/" "applications/*" "services/" "services/*" "services/*/plugins/"
	"services/*/plugins/*" "workspaces/" "workspaces/*" "services/" "services/*"
	"files/" "files/*" "consumer_groups/*/consumers/" "consumer_groups/*/consumers/*"
	"consumer_groups/" "consumer_groups/*" "consumer_groups/*/overrides/plugins/rate-limiting-advanced/"
	"consumer_groups/*/overrides/plugins/rate-limiting-advanced/*" "developers/*/applications/"
	"developers/*/applications/*" "applications/*/credentials/oauth2/" "applications/*/credentials/oauth2/*"
	"applications/*/application_instances/" "applications/*/application_instances/*"
	"applications/*/credentials/*" "applications/*/credentials/*/*"
)

# create migration admin permisions
for endpoint in "${endpoints[@]}"; do
	curl -k -X POST -H "kong-admin-token:${TOKEN}" \
		"${KONG_ADMIN_URL}/${workspace}/rbac/roles/migration-super-admin/endpoints" \
		--data "workspace=*" \
		--data "endpoint=${endpoint}" \
		--data 'actions=delete,update,read,create' \
		--data 'negative=false'
done

curl -k -X POST -H "kong-admin-token:${TOKEN}" \
	"${KONG_ADMIN_URL}/${workspace}/rbac/roles/migration-super-admin/endpoints" \
	--data 'workspace=*' \
	--data 'endpoint=kong/' \
	--data 'actions=read' \
	--data 'negative=false'

curl -k -X POST -H "kong-admin-token:${TOKEN}" \
	"${KONG_ADMIN_URL}/${workspace}/rbac/roles/migration-super-admin/endpoints" \
	--data 'workspace=*' \
	--data 'endpoint=/' \
	--data 'actions=read' \
	--data 'negative=false'

curl -k -X POST -H "kong-admin-token:${TOKEN}" \
	"${KONG_ADMIN_URL}/${workspace}/rbac/roles/migration-super-admin/endpoints" \
	--data 'workspace=*' \
	--data 'endpoint=*' \
	--data 'actions=read' \
	--data 'negative=false'

# create migration admin group
curl -i -s -k -X POST "${KONG_ADMIN_URL}/${workspace}/groups" \
	--data "comment=${workspace} Migration Admin Group" \
	--data "name=${workspace}-migration-admin" \
	-H "kong-admin-token: ${TOKEN}"
echo -e "\n"

# get workspace super admin role id
migration_admin_role_id=$(curl -s -k "${KONG_ADMIN_URL}/${workspace}/rbac/roles/migration-super-admin" \
	-H "Kong-Admin-Token: ${TOKEN}" | jq -r '.id')

# get workspace id
workspace_id=$(curl -s -k "${KONG_ADMIN_URL}/workspaces/${workspace}" \
	-H "Kong-Admin-Token: ${TOKEN}" | jq -r '.id')

# assign super admin group to role and workspace
curl -i -s -k -X POST "${KONG_ADMIN_URL}/groups/${workspace}-migration-admin/roles" \
	-H "Kong-Admin-Token: ${TOKEN}" \
	--data "rbac_role_id=${migration_admin_role_id}" \
	--data "workspace_id=${workspace_id}"
echo -e "\n"
