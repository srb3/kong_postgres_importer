#!/usr/bin/env bash
KONG_ADMIN_URL=http://localhost:8001
TOKEN=password
#set -x

declare -A ws_emails
ws_emails[default]=team-a-1@stephenb583gmail.onmicrosoft.com,team-a-2@stephenb583gmail.onmicrosoft.com,team-a-3@stephenb583gmail.onmicrosoft.com
ws_emails[mortgages]=team-b-1@stephenb583gmail.onmicrosoft.com,team-b-2@stephenb583gmail.onmicrosoft.com,team-b-3@stephenb583gmail.onmicrosoft.com
ws_emails[mobilex]=team-c-1@stephenb583gmail.onmicrosoft.com,team-c-2@stephenb583gmail.onmicrosoft.com,team-c-3@stephenb583gmail.onmicrosoft.com

declare -A ws_admin_emails
ws_admin_emails[default]=hsbc-admin@stephenb583gmail.onmicrosoft.com,hsbc-ro@stephenb583gmail.onmicrosoft
ws_admin_emails[mortgages]=mortgages-admin@stephenb583gmail.onmicrosoft.com,mortgages-ro@stephenb583gmail.onmicrosoft
ws_admin_emails[mobilex]=mobilex-admin@stephenb583gmail.onmicrosoft.com,mobilex-ro@stephenb583gmail.onmicrosoft

declare -A email_apikey
email_apikey["team-a-1@stephenb583gmail.onmicrosoft.com"]='f9b7cb22-a0e3-4e19-aaeb-c7c117800756djDscGrjGwVqA7xz'
email_apikey["team-a-2@stephenb583gmail.onmicrosoft.com"]='2cd0a56f-2c44-4a56-9f27-24aa2ac53805blH507wna4k5xEbN'
email_apikey["team-a-3@stephenb583gmail.onmicrosoft.com"]='ffe071ba-14cd-44b7-a0e0-8a5826696d81Z50Yp60ZFSMlI97q'
email_apikey["team-b-1@stephenb583gmail.onmicrosoft.com"]='902bc6bd-f128-4111-b5ea-c6557b8b0d38F+8GlXGfiV9LbePt'
email_apikey["team-b-2@stephenb583gmail.onmicrosoft.com"]='9fe8ebcc-414a-4138-900e-b4f815f2c9885qKUpUDpAskGWWBe'
email_apikey["team-b-3@stephenb583gmail.onmicrosoft.com"]='cd49eac7-009b-48f1-be8a-261f0c074777s6Sp5xucMlncUUiL'
email_apikey["team-c-1@stephenb583gmail.onmicrosoft.com"]='45fa79fc-aa44-4ca3-87d9-25f07f8e479e/7EjaVUjmSMPriFP'
email_apikey["team-c-2@stephenb583gmail.onmicrosoft.com"]='83ba58dc-38a2-4358-b579-592250aa57b401jTNkb27CKA9Wfi'
email_apikey["team-c-3@stephenb583gmail.onmicrosoft.com"]='fbab24cd-7867-46e9-a675-d7f989f00c8eRxDlffR/7rSPOc/F'

declare -A email_app
email_app["team-a-1@stephenb583gmail.onmicrosoft.com"]=team-a-1-app
email_app["team-a-2@stephenb583gmail.onmicrosoft.com"]=team-a-2-app
email_app["team-a-3@stephenb583gmail.onmicrosoft.com"]=team-a-3-app
email_app["team-b-1@stephenb583gmail.onmicrosoft.com"]=team-b-1-app
email_app["team-b-2@stephenb583gmail.onmicrosoft.com"]=team-b-2-app
email_app["team-b-3@stephenb583gmail.onmicrosoft.com"]=team-b-3-app
email_app["team-c-1@stephenb583gmail.onmicrosoft.com"]=team-c-1-app
email_app["team-c-2@stephenb583gmail.onmicrosoft.com"]=team-c-2-app
email_app["team-c-3@stephenb583gmail.onmicrosoft.com"]=team-c-3-app

declare -A email_team
email_team["team-a-1@stephenb583gmail.onmicrosoft.com"]=team-A-1
email_team["team-a-2@stephenb583gmail.onmicrosoft.com"]=team-A-2
email_team["team-a-3@stephenb583gmail.onmicrosoft.com"]=team-A-3
email_team["team-b-1@stephenb583gmail.onmicrosoft.com"]=team-B-1
email_team["team-b-2@stephenb583gmail.onmicrosoft.com"]=team-B-2
email_team["team-b-3@stephenb583gmail.onmicrosoft.com"]=team-B-3
email_team["team-c-1@stephenb583gmail.onmicrosoft.com"]=team-C-1
email_team["team-c-2@stephenb583gmail.onmicrosoft.com"]=team-C-2
email_team["team-c-3@stephenb583gmail.onmicrosoft.com"]=team-C-3

for workspace in "${!ws_emails[@]}"; do
	# create admin role
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

	# create read only role
	curl -s -k -X POST -H "kong-admin-token:${TOKEN}" \
		"${KONG_ADMIN_URL}/${workspace}/rbac/roles/" \
		--data 'name=read-only' \
		--data "comment=${workspace} read only"

	# create read only permisions
	curl -k -X POST -H "kong-admin-token:${TOKEN}" \
		"${KONG_ADMIN_URL}/${workspace}/rbac/roles/read-only/endpoints" \
		--data "workspace=${workspace}" \
		--data 'endpoint=*' \
		--data 'actions=read' \
		--data 'negative=false'

	# create admin group
	curl -i -s -k -X POST "${KONG_ADMIN_URL}/${workspace}/groups" \
		--data "comment=${workspace} Admin Group" \
		--data "name=${workspace}-admin" \
		-H "kong-admin-token: ${TOKEN}"
	echo -e "\n"

	# create read only group
	curl -i -s -k -X POST "${KONG_ADMIN_URL}/${workspace}/groups" \
		--data "comment=Read Only Group" \
		--data "name=${workspace}-ro" \
		-H "kong-admin-token: ${TOKEN}"
	echo -e "\n"

	# get workspace super admin role id
	admin_role_id=$(curl -s -k "${KONG_ADMIN_URL}/${workspace}/rbac/roles/super-admin" \
		-H "Kong-Admin-Token: ${TOKEN}" | jq -r '.id')

	# get workspace read only role id
	ro_role_id=$(curl -s -k "${KONG_ADMIN_URL}/${workspace}/rbac/roles/read-only" \
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

	# assign read only group to role and workspace
	curl -i -s -k -X POST "${KONG_ADMIN_URL}/groups/${workspace}-ro/roles" \
		-H "Kong-Admin-Token: ${TOKEN}" \
		--data "rbac_role_id=${ro_role_id}" \
		--data "workspace_id=${workspace_id}"
	echo -e "\n"

	# enable developer portal
	curl -X PATCH "http://localhost:8001/default/workspaces/${workspace}" \
		--data config.portal=true \
		-H "kong-admin-token:${TOKEN}"

	if [[ "${workspace}" == "default" ]]; then
		continue
	fi

	# patch developer portal config
	curl -k -X PATCH "${KONG_ADMIN_URL}/workspaces/${workspace}" \
		-H "Kong-Admin-Token:${TOKEN}" \
		-H 'Content-Type: application/json' \
		-d @- <<EOF
{
  "config": {
    "portal": true,
    "portal_auth": "openid-connect",
    "portal_auth_conf": {"session_cookie_domain":".localhost","verify_parameters":false,"leeway":100,"auth_methods":["authorization_code","password","session"],"redirect_uri":["http://localhost:8004/${workspace}/auth"],"login_action":"redirect","logout_redirect_uri":["http://localhost:8003/${workspace}"],"consumer_claim":["preferred_username"],"ssl_verify":false,"consumer_by":["username"],"scopes":["openid","profile","email","offline_access","${CLIENT_ID}/.default"],"logout_query_arg":"logout","client_secret":["${CLIENT_SECRET}"],"issuer":"https://login.microsoftonline.com/${TENANT_ID}/v2.0/.well-known/openid-configuration","forbidden_redirect_uri":["http://localhost:8003/${workspace}/unauthorized"],"client_id":["${CLIENT_ID}"],"logout_methods":["GET"],"login_redirect_uri":["http://localhost:8003/${workspace}"],"login_redirect_mode":"query"}
  }
}
EOF
done

# register developers
for workspace in "${!ws_emails[@]}"; do
	oldIFS=$IFS
	IFS=','
	emails="${ws_emails[$workspace]}"
	for email in $emails; do
		echo "${email}"
		curl "http://localhost:8004/${workspace}/register" -X POST \
			--data meta="{\"full_name\":\"${email_team[$email]}\"}" \
			--data email="${email}"
	done
	IFS=$oldIFS
done

# register manager users
for workspace in "${!ws_admin_emails[@]}"; do
	oldIFS=$IFS
	IFS=','
	emails="${ws_admin_emails[$workspace]}"
	for email in $emails; do
		echo "${email}"
		name="${email%%@*}"
		echo "$name"
		curl -s -k -X POST "${KONG_ADMIN_URL}/${workspace}/admins" \
			-H "Kong-Admin-Token:${TOKEN}" \
			-H "Content-Type: application/json" \
			-d "{\"email\":\"${email}\",\"username\":\"${name}\",\"custom_id\":\"${name}\",\"rbac_token_enabled\":true}"
		echo -e "\n"
	done
	IFS=$oldIFS
done

for workspace in "${!ws_emails[@]}"; do
	email="${ws_emails[$workspace]}"
	id=$(curl -s -H "kong-admin-token:${TOKEN}" \
		"${KONG_ADMIN_URL}/${workspace}/developers" | jq -r --arg EMAIL "${email}" \
		'.data[] | select(.email == $EMAIL) | "\(.id)"')

	curl -s -H "kong-admin-token:${TOKEN}" \
		"${KONG_ADMIN_URL}/${workspace}/developers/${id}/credentials/key-auth" \
		--data key="${email_apikey[$email]}"

	curl -s -H "kong-admin-token:${TOKEN}" \
		"${KONG_ADMIN_URL}/${workspace}/developers/${id}/applications" -X POST \
		--data name="${email_app[$email]}" \
		--data description="null" \
		--data redirect_uri="http://localhost"

	for app_id in $(curl -s -H "kong-admin-token:${TOKEN}" "${KONG_ADMIN_URL}/${workspace}/developers/${id}/applications" | jq -r '.data[].id'); do
		echo "${app_id}"
		for cred_id in $(curl -s -H "kong-admin-token:${TOKEN}" "${KONG_ADMIN_URL}/${workspace}/developers/${id}/applications/${app_id}/credentials/oauth2" | jq -r '.data[].id'); do
			echo "${cred_id}"
			curl -X DELETE -s \
				-H "kong-admin-token:${TOKEN}" \
				"${KONG_ADMIN_URL}/${workspace}/developers/${id}/applications/${app_id}/credentials/oauth2/${cred_id}"
		done
	done
done

for workspace in "${!ws_emails[@]}"; do
	for i in $(curl -s -H "kong-admin-token:${TOKEN}" "${KONG_ADMIN_URL}/${workspace}/plugins" | jq -r '.data[] | select(.name == "application-registration")| "\(.service.id)"'); do

		name=$(curl -s -H "kong-admin-token:${TOKEN}" "${KONG_ADMIN_URL}/${workspace}/services/${i}" | jq -r '.name')
		echo -e "running upload spec from $(pwd)"
		curl --http1.1 -s -k ${KONG_ADMIN_URL}/${workspace}/files \
			-F "path=specs/${name}.yaml" \
			-F "contents=@oas/${name}.yaml" \
			-H "kong-admin-token:${TOKEN}"

		curl -X POST "${KONG_ADMIN_URL}/${workspace}/document_objects" \
			-H "kong-admin-token:${TOKEN}" \
			--data service.id="${i}" \
			--data path="specs/${name}.yaml"

		email="${ws_emails[$workspace]}"
		id=$(curl -s -H "kong-admin-token:${TOKEN}" \
			"${KONG_ADMIN_URL}/${workspace}/developers" | jq -r --arg EMAIL "${email}" \
			'.data[] | select(.email == $EMAIL) | "\(.id)"')

		for app_id in $(curl -s -H "kong-admin-token:${TOKEN}" "${KONG_ADMIN_URL}/${workspace}/developers/${id}/applications" | jq -r '.data[].id'); do
			echo "activate instance for service id: ${i}"
			echo "for application id: ${app_id}"
			echo "on workspace: ${workspace}"
			curl -s -X POST \
				-H "kong-admin-token:${TOKEN}" \
				"${KONG_ADMIN_URL}/${workspace}/applications/${app_id}/application_instances" \
				--data service.id="${i}"
		done
	done
done
