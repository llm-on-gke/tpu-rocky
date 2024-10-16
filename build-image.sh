    SOURCE_IMAGE="projects/rocky-linux-cloud/global/images/family/rocky-linux-9-optimized-gcp"
    VARIANT="rocky"
    CUSTOM_CMDLINE="systemd.unified_cgroup_hierarchy=0" # cmdline to force cgroup1
    DISABLE_UNATTENDED_UPGRADES="TRUE"
    # run daisy workflow to generate a new image.
    ./daisy  -var:source_image=$SOURCE_IMAGE -var:variant=$VARIANT \
    -var:custom_kernel_params=$CUSTOM_CMDLINE \
    -var:disable_unattended_upgrades=$DISABLE_UNATTENDED_UPGRADES \
    build.wf.json