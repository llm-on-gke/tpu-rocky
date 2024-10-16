ZONE=us-central1-a
SOURCE_IMAGE=projects/northam-ce-mlai-tpu/global/family/v5e-rocky-linux-9
ACCELERATOR_TYPE=v5litepod-8 #v5lite-8
TPU_NAME=rick-tpu-rocky
PROJECT=northam-ce-mlai-tpu
RUNTIME_VERSION=v2-alpha-tpuv5-lite

curl -s -X POST -H "Content-Type: application/json"  -H "Authorization: Bearer $(gcloud auth print-access-token)"  -d "{
tpu: {
node_spec: {
parent: \"projects/$PROJECT/locations/$ZONE\",
node_id: \"$TPU_NAME\",
node: {
    description: 'desc',
    runtime_version:\"$RUNTIME_VERSION\",
    accelerator_type: \"$ACCELERATOR_TYPE\",
    network_config: {enable_external_ips: true},
    boot_disk: {source_image: \"$SOURCE_IMAGE\", disk_size_gb: 50},
}
}
}
}" https://tpu.googleapis.com/v2alpha1/projects/$PROJECT/locations/$ZONE/queuedResources?queuedResourceId=$TPU_NAME