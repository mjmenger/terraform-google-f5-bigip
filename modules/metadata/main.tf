terraform {
  required_version = "~> 0.12"
  required_providers {
    google = ">= 3.47"
  }
}

# Apply any required changes to metadata
locals {
  empty = {}
  as3_payloads = coalescelist(var.as3_payloads, [for i in range(0, var.num_instances) : templatefile("${path.module}/templates/as3.json",
    {}
  )])
  do_payloads = coalescelist(var.do_payloads, [for i in range(0, var.num_instances) : templatefile("${path.module}/templates/do.json",
    {
      allow_phone_home  = var.allow_phone_home,
      hostname          = length(var.hostnames) > i ? element(var.hostnames, i) : "",
      ntp_servers       = var.ntp_servers,
      dns_servers       = var.dns_servers,
      search_domains    = var.search_domains,
      timezone          = var.timezone,
      modules           = var.modules,
      analytics_metrics = format("cloudName:google,templateName:emes,templateVersion:1.1.0,region:%s,bigipVersion:%s,licenseType:%s", var.region, var.image, var.license_type)
    }
  )])
  custom_script = coalesce(var.custom_script, file("${path.module}/files/customConfig.sh"))
  startup = templatefile(var.use_cloud_init ? "${path.module}/templates/cloud_config.yml" : "${path.module}/templates/startup_script.sh",
    {
      setup_utils_sh            = base64gzip(file("${path.module}/files/setupUtils.sh")),
      multi_nic_mgt_swap_sh     = base64gzip(file("${path.module}/files/multiNicMgmtSwap.sh")),
      initial_networking_sh     = base64gzip(file("${path.module}/files/initialNetworking.sh")),
      verify_hash_tcl           = base64gzip(file("${path.module}/files/verifyHash")),
      install_cloud_libs_sh     = base64gzip(file("${path.module}/files/installCloudLibs.sh")),
      reset_management_route_sh = base64gzip(file("${path.module}/files/resetManagementRoute.sh")),
      initial_setup_sh          = base64gzip(file("${path.module}/files/initialSetup.sh")),
      application_services3_sh  = base64gzip(file("${path.module}/files/applicationServices3.sh")),
      declarative_onboarding_sh = base64gzip(file("${path.module}/files/declarativeOnboarding.sh")),
      custom_config_sh          = base64gzip(local.custom_script),
    }
  )
  cloud_init = {
    user-data = local.startup
  }
  startup_script = {
    startup-script = local.startup
  }
  ssh_keys = {
    ssh-keys = var.ssh_keys
  }
  metadata = [for i in range(0, var.num_instances) : merge(var.metadata,
    {
      enable-oslogin     = upper(var.enable_os_login)
      serial-port-enable = upper(var.enable_serial_console)
      shutdown-script = templatefile("${path.module}/templates/shutdown_script.sh",
        {}
      )
      default_gateway       = var.default_gateway
      install_cloud_libs    = join(" ", var.install_cloud_libs)
      allow_usage_analytics = upper(var.allow_usage_analytics)
      use_secrets_manager   = var.use_secrets_manager
      admin_password_key    = var.admin_password_secret_manager_key
      as3_payload           = base64gzip(element(local.as3_payloads, i))
      do_payload            = base64gzip(element(local.do_payloads, i))
    },
    var.ssh_keys != "" ? local.ssh_keys : local.empty,
    var.use_cloud_init ? local.cloud_init : local.startup_script,
  )]
}
