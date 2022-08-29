.PHONY: all mule_unit kong_unit integration_up integration_test_run integration_test_clean
SHELL := /usr/bin/env bash
IMAGE_VERSION ?= 2.8.1.1
IMAGE_BUILD ?= 0.0.13
STATE ?= identity-bridge-demo
TOPOLOGY ?= kong_gateway
# QUIET ?= true
KONG_ADMIN_URL ?= https://localhost:8444
TERRAFORM_PATH ?= docker-with-azure-ad

EF=./tests/fixtures/integration/terraform/$(TERRAFORM_PATH)/temp_files/idp_creds_env
EFT=./tests/fixtures/integration/terraform/$(TERRAFORM_PATH)/temp_files/test_creds_env

ifneq ("$(wildcard $(EF))","")
    include $(EF)
endif

ifneq ("$(wildcard $(EFT))","")
    include $(EFT)
endif

check-env:
ifndef TF_VAR_arm_tenant_id
	$(error TF_VAR_arm_tenant_id is undefined)
endif
ifndef ARM_CLIENT_ID
	$(error ARM_CLIENT_ID is undefined)
endif
ifndef ARM_CLIENT_SECRET
	$(error ARM_CLIENT_SECRET is undefined)
endif
ifndef ARM_TENANT_ID
	$(error ARM_TENANT_ID is undefined)
endif
ifndef ARM_SUBSCRIPTION_ID
	$(error ARM_SUBSCRIPTION_ID is undefined)
endif

integration_make_ready: integration_up integration_manager_login


integration_up: check-env
	@echo "brining up integration environment"; \
	source ./tests/fixtures/integration/terraform/$(TERRAFORM_PATH)/temp_files/test_creds_env; \
	pushd ./tests/fixtures/integration/; \
	./topology.sh up $(STATE) $(TOPOLOGY) $(IMAGE_BUILD); \
	popd;

integration_down: check-env
	@echo "destroying integration environment"; \
	source ./tests/fixtures/integration/terraform/$(TERRAFORM_PATH)/temp_files/test_creds_env; \
	pushd ./tests/fixtures/integration/; \
	./topology.sh down $(STATE) $(TOPOLOGY) $(IMAGE_BUILD); \
	popd;

integration_down_skip_tf:
	@echo "destroying integration environment"; \
	source ./tests/fixtures/integration/terraform/$(TERRAFORM_PATH)/temp_files/test_creds_env; \
	pushd ./tests/fixtures/integration/; \
	SKIP_TF=True QUIET=$(QUIET) ./topology.sh down $(STATE) $(TOPOLOGY) $(IMAGE_BUILD); \
	popd;

integration_up_skip_tf:
	@echo "creating integration environment"; \
	source ./tests/fixtures/integration/terraform/$(TERRAFORM_PATH)/temp_files/test_creds_env; \
	pushd ./tests/fixtures/integration/; \
	SKIP_TF=True QUIET=$(QUIET) ./topology.sh up $(STATE) $(TOPOLOGY) $(IMAGE_BUILD); \
	popd;

integration_manager_login:
	@echo "running integration tests"; \
	source ./tests/fixtures/integration/terraform/$(TERRAFORM_PATH)/temp_files/test_creds_env; \
	source ./tests/fixtures/integration/terraform/$(TERRAFORM_PATH)/temp_files/idp_creds_env; \
	if [[ -z "$$CI_MODE" ]]; \
	then \
		source $(HOME)/.local/bin/virtualenvwrapper.sh; \
  	mktmpenv -i selenium; \
		cd -; \
	fi; \
	  python ./tests/fixtures/integration/scripts/manager_login/manager_login.py; \
	if [[ -z "$$CI_MODE" ]]; \
	then \
		deactivate; \
	fi;

integration_manager_login_chromium:
	@echo "running integration tests"; \
	source ./tests/fixtures/integration/terraform/$(TERRAFORM_PATH)/temp_files/test_creds_env; \
	source ./tests/fixtures/integration/terraform/$(TERRAFORM_PATH)/temp_files/idp_creds_env; \
	if [[ -z "$$CI_MODE" ]]; \
	then \
		source $(HOME)/.local/bin/virtualenvwrapper.sh; \
  	mktmpenv -i selenium -i webdriver-manager; \
		cd -; \
	fi; \
	  python ./tests/fixtures/integration/scripts/manager_login/manager_login_chromium.py; \
	if [[ -z "$$CI_MODE" ]]; \
	then \
		deactivate; \
	fi;


script_run:
	@echo "running import test"; \
	source ./tests/fixtures/integration/terraform/$(TERRAFORM_PATH)/temp_files/test_creds_env; \
	python ./runner.py \
	--config-file $(CONFIG_FILE_PATH) \
	--hostname $(DB_HOSTNAME) \
	--database $(DB_NAME) \
	--username $(DB_USERNAME) \
  --password $(DB_PASSWORD);


script_clean:
	@echo "running delete test"; \
	source ./tests/fixtures/integration/terraform/$(TERRAFORM_PATH)/temp_files/test_creds_env; \
	python ./runner.py \
	--config-file $(CONFIG_FILE_PATH) \
	--hostname $(DB_HOSTNAME) \
	--database $(DB_NAME) \
	--username $(DB_USERNAME) \
  --password $(DB_PASSWORD) \
	--delete;

ci_prep:
	@echo "Prepping the environment for CI"; \
  mkdir $$HOME/bin/; \
  curl -L -o /tmp/geckodriver.tar.gz https://github.com/mozilla/geckodriver/releases/download/v0.31.0/geckodriver-v0.31.0-linux64.tar.gz; \
  tar xzf /tmp/geckodriver.tar.gz -C $$HOME/bin/; \
	pip install -r requirements/ci.txt;

