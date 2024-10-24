# tpu-rocky

## Manual Rocky Linux Based TPU-VM Image / VM Creation

These are best-effort instructions for manually creating a Rocky Linux based
custom image for TPU VMs. They are
meant to provide documentation of all the necessary components. We suggest
fully understanding these components prior to using.

### Prerequisites
1. Install Go build environment, if it does not have it yet
2. Daisy build tool installation.
```
git clone https://github.com/GoogleCloudPlatform/compute-daisy
cd compute-daisy
go mod download
CGO_ENABLED=0 go build -v -o /go/bin/daisy cli/main.go
cp /go/bin/daisy /usr/local/bin
```

### Build TPU VM Rocky Image
- download this repo 
```
git clone https://github.com/llm-on-gke/tpu-rocky
cd tpu-rocky
```
- update build.wf.josn file
  line 3 and 124: "Project": "northam-ce-mlai-tpu", #
  line 4: "Zone": "us-central1-a",
  line 5: "GCSPath": "gs://rick-rocky-tpu-image/daisy/tpu_vm_images"
- Run shell:
  ```
  bash build-image.sh
  ```
### Create TPU VM:
Update create-tpu-vm.sh on line 1-5:
```
ZONE=us-central1-a
SOURCE_IMAGE=projects/northam-ce-mlai-tpu/global/family/tpu-vm-rocky #v5e-rocky-linux-9
ACCELERATOR_TYPE=v5litepod-8 #v5lite-8
TPU_NAME=rick-tpu-rocky
PROJECT=northam-ce-mlai-tpu
```
Run the shell command to create TPU VM:
```
bash create-tpu-vm.sh
```








