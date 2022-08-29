variable "ad_application_name" {
  description = "the name of the azure ad application"
  type        = string
  default     = "kong-manager-migration"
}

variable "arm_tenant_id" {
  description = "The Azure tenant ID"
  type        = string
}

variable "admin_user" {
  description = "The name of one of the manager users to act as the test user"
  type        = string
  default     = "kong_admin"
}

variable "config_file_path" {
  description = "The path to the kong_importer config file"
  type        = string
  default     = "temp_files/config.yaml"
}

variable "db_hostname" {
  description = "The hostname of the Kong database"
  type        = string
  default     = "127.0.0.1"
}

variable "db_name" {
  description = "The name of the Kong database"
  type        = string
  default     = "kong"
}

variable "db_username" {
  description = "The username to access the Kong database"
  type        = string
  default     = "kong"
}

variable "db_password" {
  description = "The password to access the Kong database"
  type        = string
  default     = "kong"
}

variable "number_of_workspaces" {
  description = "The number of workspaces to create in Kong"
  type        = number
  default     = 100
}

variable "prefix" {
  description = "A string value to prefix entities with"
  type        = string
  default     = "perf"
}

variable "number_of_consumers" {
  description = "The number of consumers to create in each workspace"
  type        = number
  default     = 50
}

variable "number_of_services" {
  description = "The number of services to create in each workspace"
  type        = number
  default     = 40
}

variable "number_of_routes" {
  description = "The number of routes to create in each workspace"
  type        = number
  default     = 7
}

variable "service_protocol" {
  description = "The protocol to use for all services"
  type        = string
  default     = "http"
}

variable "service_host" {
  description = "The hostname to use for all services"
  type        = string
  default     = "httpbin.org"
}

variable "service_port" {
  description = "The port to use for all services"
  type        = string
  default     = "80"
}

variable "service_path" {
  description = "The path to use for all services"
  type        = string
  default     = "/"
}

variable "mem_cache_size" {
  description = "The size of the Kong mem_cache_size setting"
  type        = string
  default     = "128m"
}

variable "manager_users" {
  description = "A map of users to create in azure ad"
  type = map(object({
    email      = string
    first_name = string
    last_name  = string
    password   = string
    workspaces = list(string)
    groups     = list(string)
  }))
  default = {}
}

