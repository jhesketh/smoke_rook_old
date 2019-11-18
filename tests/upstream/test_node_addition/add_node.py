#!/usr/bin/env python3

import network
import node
import os
import time
import virsh


#
# variables
#

# this can be set to allow multiple clusters on one URI without collisions
CLUSTER_PREFIX = os.getenv("CLUSTER_PREFIX", os.getlogin() + '-')

LIBVIRT_URI                 = os.getenv("LIBVIRT_URI", "qemu:///system")
LIBVIRT_IMAGE_DOWNLOAD_POOL = os.getenv("LIBVIRT_IMAGE_DOWNLOAD_POOL", "default")
LIBVIRT_OS_VOL_POOL         = os.getenv("LIBVIRT_OS_VOL_POOL", "default")
LIBVIRT_ROOK_VOL_POOL       = os.getenv("LIBVIRT_ROOK_VOL_POOL", "default")

NUM_MASTERS = int(os.getenv("NUM_MASTERS", "1"))
NUM_WORKERS = int(os.getenv("NUM_WORKERS", "2"))

NODE_OS_IMAGE            = os.getenv("NODE_OS_IMAGE",
    "https://download.opensuse.org/distribution/leap/15.0/jeos/openSUSE-Leap-15.0-JeOS.x86_64-15.0.1-OpenStack-Cloud-Current.qcow2")
NODE_VCPUS               = int(os.getenv("NODE_VCPUS", "2"))
NODE_RAM_MB              = int(os.getenv("NODE_RAM_MB", "2048"))
NODE_MIN_OS_DISK_SIZE    = int(os.getenv("NODE_MIN_OS_DISK_SIZE", "30"))
NODE_ROOK_VOLUMES        = int(os.getenv("NODE_ROOK_VOLUMES", "2"))
NODE_ROOK_VOLUME_SIZE_GB = int(os.getenv("NODE_ROOK_VOLUME_SIZE_GB", "10"))

# network will be named <CLUSTER_PREFIX><NET_DOMAIN_NAME>,
# e.g., 'user-rook-dev.net' if CLUSTER_PREFIX="user-"
NET_DOMAIN_NAME = os.getenv("NET_DOMAIN_NAME", "rook-dev.net")
NET_CIDR = os.getenv("NET_CIDR", "172.60.0.0/22")

osImageName = virsh.DownloadImageToVolume(
    LIBVIRT_URI, NODE_OS_IMAGE, LIBVIRT_IMAGE_DOWNLOAD_POOL)

FULL_NET_DOMAIN_NAME = CLUSTER_PREFIX + NET_DOMAIN_NAME

k8sNet = network.LvmNetwork(
    networkName=FULL_NET_DOMAIN_NAME, domainName=FULL_NET_DOMAIN_NAME,
    networkWithCIDR=NET_CIDR)

# all nodes have the same config
hwConfig = node.HardwareConfig(cpus=NODE_VCPUS, ram_MB=NODE_RAM_MB)
osConfig = node.OSConfig(
    parentImage=osImageName, parentImagePool=LIBVIRT_IMAGE_DOWNLOAD_POOL,
    createdDiskPool=LIBVIRT_OS_VOL_POOL, minSizeGB=NODE_MIN_OS_DISK_SIZE)
volConfig = node.VolumeConfig(
    count=NODE_ROOK_VOLUMES, sizeGB=NODE_ROOK_VOLUME_SIZE_GB,
    pool=LIBVIRT_ROOK_VOL_POOL)
netConfigs = [node.NetworkConfig(k8sNet.networkName)]

n = node.LvmDomain(CLUSTER_PREFIX + "k8s-worker-new", hwConfig, osConfig,
                   volConfig, netConfigs)

n.Create(LIBVIRT_URI)


TIMEOUT = 5 * 60
sTime = time.time()
leases = network.ListNetworkDHCPLeases(LIBVIRT_URI, k8sNet.networkName)
print("Waiting {} minutes for cluster nodes to have DHCP leases ...".format(int(TIMEOUT/60)), end="", flush=True)
while len(leases) < NUM_MASTERS + NUM_WORKERS:
    if time.time() - sTime > TIMEOUT:
        print(" timed out!")
        exit(1)
    time.sleep(5)
    print(".", end="", flush=True)
    leases = network.ListNetworkDHCPLeases(LIBVIRT_URI, k8sNet.networkName)
print(" done.")


print("Node IP:")
print(leases[n.name])

with open('/tmp/test_node_addition/_node-list-extra', 'w') as f:
    f.writelines(
        [
            "#!/usr/bin/env bash\n",
            'export new_worker="%s"\n' % (leases[n.name])
        ]
    )
