#!/bin/bash
#!/usr/bin/env bash

# Run ./bind_to_vfio_pci.sh <DBDF>
# Binds the device at <DBDF> to vfio-pci.
# If the device is already bound to a driver, unbinds it first.

# load the vfio-pci module into the kernel. no-op if already loaded.
sudo modprobe vfio-pci

DBDF_REGEX="^[[:xdigit:]]{4}:[[:xdigit:]]{2}:[[:xdigit:]]{2}.[[:xdigit:]]$"

unset BDF
if [[ $1 =~ $DBDF_REGEX ]]; then
    BDF=$1
else
    echo "Error: BDF arg ($1) is not in form dddd:bb:dd.f"
    exit 1
fi

PCI_PATH="/sys/bus/pci/devices/$BDF"

echo "vfio-pci" | sudo tee "$PCI_PATH/driver_override"

PCI_DRIVER_PATH="$PCI_PATH/driver"
if [[ -d "$PCI_DRIVER_PATH" ]]; then
    curr_driver=$(readlink "$PCI_DRIVER_PATH")
        curr_driver=${curr_driver##*/}
    if [[ $curr_driver == "vfio-pci" ]]; then
        echo "$BDF already bound to vfio-pci"
        exit 0
    else
        echo "$BDF" | sudo tee "$PCI_DRIVER_PATH/unbind"
        if [[ -d "$PCI_DRIVER_PATH" ]]; then
            echo "Error: Unable to unbind $PCI_DRIVER_PATH"
            exit 1
        fi
        echo "Unbound $BDF from driver $curr_driver"
    fi
fi
echo "$BDF" | sudo tee /sys/bus/pci/drivers_probe
echo "Bound $BDF to vfio-pci"

# grant RW access on VFIO device to all users
IOMMU_GROUP=$(readlink "$PCI_PATH/iommu_group" | xargs basename)
VFIO_DEV="/dev/vfio/$IOMMU_GROUP"
if [[ -c "$VFIO_DEV" ]]; then
    sudo chmod 0666 "$VFIO_DEV"
else
    echo "$VFIO_DEV not found"
    exit 1
fi

echo 1 | sudo tee /sys/module/vfio_iommu_type1/parameters/allow_unsafe_interrupts