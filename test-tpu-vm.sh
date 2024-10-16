#!/bin/bash
set -x

export enable_profiling=false
export accelerator_type=v5lite-4 
export tpu_premapped_buffer_size=4294967296

# Retries command until successful or up to n attempts and sleeps for N seconds
# between the attempts.
function retry_constant_custom() {
  local -r max_retries="$1"
  local -r retry_delay="$2"
  local -r cmd=("${@:3}")

  echo "About to run '${cmd[*]}' with retries..."
  for ((i = 1; i < ${max_retries}; i++)); do
    if "${cmd[@]}"; then
      echo "'${cmd[*]}' succeeded after ${i} execution(s)."
      return 0
    fi
    sleep "${retry_delay}"
  done

  echo "Final attempt of '${cmd[*]}'..."
  # Let any final error propagate all the way out to any error traps.
  "${cmd[@]}"
}

export ACCELERATOR_TYPE=$accelerator_type

python -m pip install --upgrade pip
python -m pip install --upgrade setuptools wheel twine check-wheel-contents
pip install setuptools[core]

# Install the python packages:
echo -e '
tensorflow
tensorflow-datasets
clu
flax
jax[tpu]
-f https://storage.googleapis.com/jax-releases/libtpu_releases.html
' > requirements.txt
retry_constant_custom 5 30 pip install --no-cache-dir -q -q -r requirements.txt

# Show all Python packages:
pip list

# download patched flax version
gsutil cp gs://cloud-tpu-v2-images-dev-artifacts/starfish-e2e/flax-jax-4.10.tar.gz .
tar xzf flax-jax-4.10.tar.gz -C .
rm flax-jax-4.10.tar.gz

sudo dnf -y install numactl

# if $tpu_library_path is not empty, override libtpu path.
if [[ -f "$tpu_library_path" ]]; then
  export TPU_LIBRARY_PATH=$tpu_library_path
fi
export TPU_PREMAPPED_BUFFER_SIZE=$tpu_premapped_buffer_size
export JAX_USE_PJRT_C_API_ON_TPU=1
export JAX_PLATFORMS=tpu,cpu
export TPU_VMODULE=singleton_tpu_system_manager=10,tpu_version_flag=10,device_util=10,device_scanner=10,mesh_builder=10,master=10
numactl --cpunodebind=0 --membind=0 python3 flax/examples/imagenet/imagenet_fake_data_benchmark.py --enable_profiling="$enable_profiling"