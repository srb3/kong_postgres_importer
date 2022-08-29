#!/usr/bin/env bash
MODE=${1:-up}
STATE=${2:-identity-bridge-demo}
TOPOLOGY=${3:-kong_gateway}
IMAGE_BUILD=${4:-local}
TPATH=${TERRAFORM_PATH:-docker-with-azure-ad}
IMAGE_VERSION=${IMAGE_VERSION:-2.8.1.1}

export DECK_LOG_TIMEOUT=${DECK_LOG_TIMEOUT:-10000}
export DECK_LOG_RETRY_COUNT=${DECK_LOG_RETRY_COUNT:-3}
export DECK_LOG_QUEUE_SIZE=${DECK_LOG_QUEUE_SIZE:-4000}

# echo "log timeout set to: $DECK_LOG_TIMEOUT"

if [[ "${IMAGE_BUILD}" != "local" ]]; then
	image_build="${IMAGE_BUILD}"
else
	image_build="local"
fi

if [[ "${MODE}" == "up" ]]; then
	if [[ -z "${SKIP_TF}" ]]; then
		pushd "./terraform/${TPATH}" || exit
		terraform init
		terraform apply -auto-approve
		popd || exit
	fi
	source "./terraform/${TPATH}/temp_files/idp_creds_env"
	source "./terraform/${TPATH}/temp_files/env_auth_conf"
elif [[ "${MODE}" == "down" ]]; then
	if [[ -z "${SKIP_TF}" ]]; then
		pushd "./terraform/${TPATH}" || exit
		terraform destroy --auto-approve
		popd || exit
	fi
fi

if [[ -n "${QUIET}" ]]; then
	export QUIET=true
fi

export KONG_PORTAL_APP_AUTH=kong-oauth2

if [[ "${image_build}" == "local" ]]; then
	IMAGE=kong/kong-gateway
	VERSION=${IMAGE_VERSION}-rhel7
elif [[ "${image_build}" == "test" ]]; then
	IMAGE=kongcx/kong-test-custom
	VERSION="${IMAGE_VERSION}-rhel7-${TEST_VERSION}"
else
	IMAGE=kongcx/kong-custom
	VERSION="${IMAGE_VERSION}-rhel7-${image_build}"
fi

if [[ "${TOPOLOGY}" == "kong_gateway" ]]; then
	QUIET="${QUIET}" \
		ACCESS_LOG="/dev/stdout" \
		ERROR_LOG="/dev/stderr" \
		SCRIPT=${STATE} \
		DECK_CONFIG=${STATE} \
		KONG_LOG_LEVEL=debug \
		KONG_IMAGE=${IMAGE} \
		KONG_VERSION=${VERSION} \
		PLUGINS=bundled,splunk-hec,rate-limiting-advanced-sidecar,gateway-identity-bridge,sidecar-identity-bridge,request-termination-ext \
		DMODE=${MODE} \
		./start.sh "${TOPOLOGY}"
fi
