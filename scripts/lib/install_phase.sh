# shellcheck shell=bash

install() {
  log INFO "Install phase start"
  run_phase_hooks "pre-install"

  install_dirs
  install_eula
  install_server        # server jar
  clear_fabric_cache
  setup_server_icon

  configure_paper_configs
  generate_velocity_toml

  handle_reset_world_flag
  install_world

  install_server_properties
  install_mods          # mods (most important)
  activate_mods         # activate mods
  install_datapacks     # datapacks
  activate_datapacks    # activate datapacks
  install_jvm_args
  install_configs
  activate_configs
  apply_paper_global_from_env
  install_plugins
  activate_plugins
  if [[ ! "${TYPE}" == "velocity" ]]; then
    install_resourcepacks
    activate_resourcepacks
  fi
  install_modpack
  install_c2me_jvm_args
  install_whitelist
  install_ops
  configure_c2me_opencl
  run_phase_hooks "post-install"

  log INFO "Install phase completed"
}
