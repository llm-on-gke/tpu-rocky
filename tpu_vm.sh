#!/bin/bash
export HOME=/tmp
cd $HOME
URL="http://metadata/computeMetadata/v1/instance/attributes"
daisy_sources="$(curl -f -H Metadata-Flavor:Google ${URL}/daisy-sources-path)"
variant="$(curl -f -H Metadata-Flavor:Google ${URL}/variant)"
custom_kernel_params="$(curl -f -H Metadata-Flavor:Google ${URL}/custom_kernel_params)"
disable_unattended_upgrades="$(curl -f -H Metadata-Flavor:Google ${URL}/disable_unattended_upgrades)"
# apt packages to install on the image.
base_vm_packages="git vim gcc python3-devel python3-pip g++ unzip python3-packaging cloud-init"
echo "Status: Executing startup script on a image with kernel version: $(uname -r)"
# install gcc-12 on image with linux kernel > 5.15.
# gcc-12 is needed to compile the TPU drivers on these kernel versions.
if dpkg --compare-versions "$(uname -r)" "ge" "5.16"; then
  base_vm_packages="${base_vm_packages} gcc-12"
fi
pip_packages="cython requests virtualenv setuptools pyYAML==5.4.1"

sudo su

sudo ln -s python python3

# Install base VM packages via apt-get
sudo dnf -y update
# shellcheck disable=SC2086
sudo dnf -y install $base_vm_packages
if [[ $? -ne 0 ]]; then
  echo "BuildFailed: Unable to install packages."
  exit 1
fi

# Install pip packages. Instead of individual pip packages, prefer to add it
# on the list above. As pip installer now have an updated dependency resolver.
# shellcheck disable=SC2086
pip3 install --upgrade $pip_packages
if [[ $? -ne 0 ]]; then
  echo "BuildFailed: Unable to install pip packages."
  exit 1
fi

# Install and configure docker-credential-gcr
# TODO(amangu): Refactor this installation process to use commands from:
# go/installdocker#standalone-for-gcloud-less-environments
VERSION=2.0.0
OS=linux  # or "darwin" for OSX, "windows" for Windows.
ARCH=amd64  # or "386" for 32-bit OSs, "arm64" for ARM 64.

sudo curl -fsSL "https://github.com/GoogleCloudPlatform/docker-credential-gcr/releases/download/v${VERSION}/docker-credential-gcr_${OS}_${ARCH}-${VERSION}.tar.gz" \
  | sudo tar xz ./docker-credential-gcr 
sudo mv ./docker-credential-gcr /usr/bin/docker-credential-gcr && sudo chmod +x /usr/bin/docker-credential-gcr
if [[ $? -ne 0 ]]; then
  echo "BuildFailed: Unable to install docker-credential-gcr."
  exit 1
fi
/usr/bin/docker-credential-gcr configure-docker

# Install docker
echo "Installing docker."
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf -y update
sudo dnf -y install docker-ce docker-ce-cli containerd.io
sudo systemctl --now enable docker

sudo docker run --rm hello-world
if [[ $? -ne 0 ]]; then
  echo "BuildFailed: docker install failed."
fi

# Workaround cloudinit not setting uid
useradd -u 2000 tpu-runtime
# Workaround cloudinit not creating homedir
mkhomedir_helper tpu-runtime

# Allow any user to access the tpu device, also requires a single process having a lot of memory
echo 'KERNEL=="accel*" MODE="0666"' | sudo tee -a /etc/udev/rules.d/99-tpu.rules
echo '*  hard  memlock  unlimited' | sudo tee -a /etc/security/limits.conf
echo '*  soft  memlock  unlimited' | sudo tee -a /etc/security/limits.conf

# prevent CPU from moving into low power idle state
# enable intel_iommu in TPU v5 base images - Rocky support is only expected for v5+
kernel_cmdline="$idle=poll intel_iommu=on,sm_on";
# Append any cmdlines passed in as workflow param.
# NOTE: If setting custom_kernel_params to a non-empty value, exercise caution
# and test thoroughly as the kernel params can significantly 
# modify a VM's behavior.
# TODO(b/323294263): Add validation to TPU base VM script/generated image.
if [[ ! -z "${custom_kernel_params}" ]]; then
  kernel_cmdline="${kernel_cmdline} ${custom_kernel_params}";
fi
sed -i "s/GRUB_CMDLINE_LINUX=\"\"/GRUB_CMDLINE_LINUX=\"${kernel_cmdline}\"/" /etc/default/grub
echo "Status: New kernel cmdline: $(cat /etc/default/grub | grep -e '^GRUB_CMDLINE_LINUX=')"
grub2-mkconfig -o /boot/efi/EFI/rocky/grub.cfg

# bug(b/227455264): Fix for gsutil not working
echo "CLOUDSDK_PYTHON=/usr/bin/python3" | sudo tee -a /etc/environment

# Install tcmalloc (b/182915380#comment78).
sudo dnf install -y epel-release
sudo dnf config-manager --enable crb
sudo dnf install -y gperftools
echo "LD_PRELOAD=\"/usr/lib64/libtcmalloc.so.4\"" | sudo tee -a /etc/environment

# udev rules to bind TPU V5x chips to vfio-pci
sudo gsutil cp "${daisy_sources}/bind_to_vfio_pci.sh" /lib/udev/bind_to_vfio_pci.sh
if [[ $? -ne 0 ]]; then
  echo ${daisy_sources}
  echo "BuildFailed: Unable to copy the packages."
  errormessage=$(sudo gsutil cp "${daisy_sources}/bind_to_vfio_pci.sh" /lib/udev/bind_to_vfio_pci.sh 2>&1)
  echo $errormessage
  exit 1
fi
sudo chmod +x /lib/udev/bind_to_vfio_pci.sh
sudo gsutil cp "${daisy_sources}/99-tpu-vfiopci.rules" /etc/udev/rules.d/99-tpu-vfiopci.rules

echo "Status: Installed udev rules to bind compatible TPUs to vfio-pci"

# Bump default ulimit.
echo "*    soft    nofile       100000" | sudo tee -a /etc/security/limits.conf
echo "*    hard    nofile       100000" | sudo tee -a /etc/security/limits.conf
echo "root soft    nofile       100000" | sudo tee -a /etc/security/limits.conf
echo "root hard    nofile       100000" | sudo tee -a /etc/security/limits.conf

# Setting the right security context for cloud-init to access the needed files.

# for tpu-env file. I think the `TYPE` could be `unconfined_t` here. As using `file_t` seems to result in `unlabeled_t`.
sudo touch /home/tpu-runtime/tpu-env
sudo semanage fcontext -a -t file_t '/home/tpu-runtime/tpu-env'
sudo chcon -Rv -u system_u -t file_t '/home/tpu-runtime/tpu-env'
sudo restorecon -Rv '/home/tpu-runtime/tpu-env'


# for docker-credential-helper
sudo touch /usr/bin/docker-credential-gcr
sudo semanage fcontext -a -t bin_t '/usr/bin/docker-credential-gcr'
sudo chcon -Rv -u system_u -t bin_t '/usr/bin/docker-credential-gcr'
sudo restorecon -R -v '/usr/bin/docker-credential-gcr'


# Download agent images
echo "Status: Pre-fetching Health Agent..."
docker pull gcr.io/cloud-tpu-v2-images/tpu_agents:280736970
if [[ $? -ne 0 ]]; then
  echo "BuildFailed: Unable to pull tpu_agents (health agent)."
  exit 1
fi
echo "Status: Pre-fetching Instance Agent..."
docker pull gcr.io/cloud-tpu-v2-images/instance_agent:20210419
if [[ $? -ne 0 ]]; then
  echo "BuildFailed: Unable to pull instance agent"
  exit 1
fi
echo "Status: Pre-fetching Collectd Agent..."
docker pull gcr.io/cloud-tpu-v2-images/collectd-agent:225018473
if [[ $? -ne 0 ]]; then
  echo "BuildFailed: Unable to pull collectd agent"
  exit 1
fi
echo "Status: Pre-fetching Fluentd Agent..."
docker pull gcr.io/cloud-tpu-v2-images/fluentd-agent:236381202
if [[ $? -ne 0 ]]; then
  echo "BuildFailed: Unable to pull fluentd agent"
  exit 1
fi
echo "Status: Pre-fetching Monitoring Agent..."
docker pull gcr.io/cloud-tpu-v2-images/monitoring_agent:cl_367332558
if [[ $? -ne 0 ]]; then
  echo "BuildFailed: Unable to pull monitoring agent"
  exit 1
fi
echo "Status: Pre-fetching Runtime Monitor Agent..."
docker pull gcr.io/cloud-tpu-v2-images/runtime_monitor:326941532
if [[ $? -ne 0 ]]; then
  echo "BuildFailed: Unable to pull runtime monitor agent"
  exit 1
fi

cat << EOF > cloud-user.cfg
#cloud-config
users:
  - name: tpu-cloud-user
    lock_passwd: false
    gecos: Rocky Cloud User
    groups: [wheel, root, adm, systemd-journal]
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    shell: /bin/bash
EOF

sudo mkdir -p /etc/cloud/cloud.cfg.d/
sudo mv cloud-user.cfg /etc/cloud/cloud.cfg.d/cloud-user.cfg

echo "%wheel        ALL=(ALL)       NOPASSWD: ALL" | (sudo su -c 'EDITOR="tee" visudo -f /etc/sudoers.d/wheel')
echo "%root        ALL=(ALL)       NOPASSWD: ALL" | (sudo su -c 'EDITOR="tee -a" visudo -f /etc/sudoers.d/wheel')

# Increasing timeout duration based on b/275099912
echo "GCS_RESOLVE_REFRESH_SECS=60" | sudo tee -a /etc/environment
echo "GCS_REQUEST_CONNECTION_TIMEOUT_SECS=300" | sudo tee -a /etc/environment
echo "GCS_METADATA_REQUEST_TIMEOUT_SECS=300" | sudo tee -a /etc/environment
echo "GCS_READ_REQUEST_TIMEOUT_SECS=300" | sudo tee -a /etc/environment
echo "GCS_WRITE_REQUEST_TIMEOUT_SECS=600" | sudo tee -a /etc/environment

# disable unattended-upgrades - seems only for Ubuntu.

echo "Preload done." > /dev/ttyS0
