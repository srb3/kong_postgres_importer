########### Providers ############################

provider "azuread" {}

########### Kong configuration ###################

locals {
  manager_users = var.manager_users

  domain = "localhost"

  azure_ad_multi_user = true

  manager_redirect_uris = [
    "http://localhost:8001/",
    "http://localhost:8004/*",
    "http://localhost:8005/*",
  ]

  admin_gui_auth_conf = templatefile("${path.module}/templates/auth_conf", {
    oidc_client_secret = module.ad-manager.client_secret
    oidc_client_id     = module.ad-manager.client_id
    issuer             = module.ad-manager.metadata-url
    manager_url        = "http://localhost:8002/"
  })

  portal_auth_conf = templatefile("${path.module}/templates/portal_auth_conf", {
    domain             = local.domain
    oidc_client_secret = module.ad-manager.client_secret
    oidc_client_id     = module.ad-manager.client_id
    issuer             = module.ad-manager.metadata-url
    portal_url         = "http://localhost:8003"
    portalapi_url      = "http://localhost:8004"
    workspace          = "default"
  })

  admin_gui_session_conf = templatefile("${path.module}/templates/session_conf", {
    admin_session_cookie_secret = "supersecret"
    cookie_secure               = "false"
    domain                      = local.domain
  })

  portal_session_conf = templatefile("${path.module}/templates/portal_session_conf", {
    portal_session_cookie_secret = "supersecret"
    cookie_secure                = "false"
    domain                       = local.domain
  })

  idp_creds_env = templatefile("${path.module}/templates/idp_creds_env", {
    client_id     = module.ad-manager.client_id
    client_secret = module.ad-manager.client_secret
    tenant_id     = var.arm_tenant_id
    admin_user    = var.admin_user
    admin_pass    = var.manager_users[var.admin_user].password
    admin_email   = var.manager_users[var.admin_user].email
  })

  test_creds_env = templatefile("${path.module}/templates/test_creds_env", {
    config_file_path = "${abspath(path.module)}/${var.config_file_path}"
    db_hostname      = var.db_hostname
    db_name          = var.db_name
    db_username      = var.db_username
    db_password      = var.db_password
    mem_cache_size   = var.mem_cache_size
  })

  config_file = templatefile("${path.module}/templates/config.yaml", {
    number_of_workspaces = var.number_of_workspaces
    prefix               = var.prefix
    number_of_consumers  = var.number_of_consumers
    number_of_services   = var.number_of_services
    number_of_routes     = var.number_of_routes
    service_protocol     = var.service_protocol
    service_host         = var.service_host
    service_port         = var.service_port
    service_path         = var.service_path
  })

  kong_idp_creds_env = templatefile("${path.module}/templates/env_auth_conf", {
    domain             = local.domain
    oidc_client_secret = module.ad-manager.client_secret
    oidc_client_id     = module.ad-manager.client_id
    issuer             = module.ad-manager.metadata-url
    portal_url         = "http://localhost:8003"
    portalapi_url      = "http://localhost:8004"
    workspace          = "default"
    manager_url        = "http://localhost:8002/"
  })

}

########### Azure AD #############################

module "ad-manager" {
  source                         = "srb3/ad/azure"
  version                        = "0.0.6"
  display_name                   = var.ad_application_name
  redirect_uris                  = local.manager_redirect_uris
  multi_user                     = local.azure_ad_multi_user
  users                          = local.manager_users
  requested_access_token_version = 2
}

resource "local_file" "auth_conf" {
  content         = local.admin_gui_auth_conf
  filename        = "${path.module}/temp_files/auth_conf"
  file_permission = "0644"
}

resource "local_file" "session_conf" {
  content         = local.admin_gui_session_conf
  filename        = "${path.module}/temp_files/session_conf"
  file_permission = "0644"
}

resource "local_file" "portal_auth_conf" {
  content         = local.portal_auth_conf
  filename        = "${path.module}/temp_files/portal_auth_conf"
  file_permission = "0644"
}

resource "local_file" "portal_session_conf" {
  content         = local.portal_session_conf
  filename        = "${path.module}/temp_files/portal_session_conf"
  file_permission = "0644"
}

resource "local_file" "idp_creds_env" {
  content         = local.idp_creds_env
  filename        = "${path.module}/temp_files/idp_creds_env"
  file_permission = "0644"
}

resource "local_file" "test_creds_env" {
  content         = local.test_creds_env
  filename        = "${path.module}/temp_files/test_creds_env"
  file_permission = "0644"
}

resource "local_file" "config_file" {
  content         = local.config_file
  filename        = "${path.module}/${var.config_file_path}"
  file_permission = "0644"
}

resource "local_file" "env_auth_conf" {
  content         = local.kong_idp_creds_env
  filename        = "${path.module}/temp_files/env_auth_conf"
  file_permission = "0644"
}
