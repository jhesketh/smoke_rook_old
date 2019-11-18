#!/usr/bin/env bash

export JOB_ROOT=`dirname "$(realpath "$0")"`
export SMOKE_ROOK_ROOT=`realpath "$JOB_ROOT/../../../"`
source $SMOKE_ROOK_ROOT/common/common.sh

export DEV_ROOK_CEPH=$SMOKE_ROOK_ROOT/vendor/dev-rook-ceph

#TODO(jhesketh): Fix the vendoring of DEV_ROOK_CEPH
mkdir -p /tmp/test_node_addition
python3 $JOB_ROOT/add_node.py
OCTOPUS=$DEV_ROOK_CEPH/.tools/octopus-v2.0.1
BASH_CMD=bash

#TODO(jhesketh): Fix the way octopus hosts are used
O_params="--groups-file /tmp/test_node_addition/_node-list-extra --identity-file $DEV_ROOK_CEPH/scripts/resources/.ssh/id_rsa --host-groups new_worker"


#TODO(jhesketh): delete the duplication of below / make scripts from dev more reusable


source $DEV_ROOK_CEPH/scripts/shared.sh

wait_for "new node to be up and ready" 90 \
  "${OCTOPUS} $O_params run 'hostname' 2>&1 && \
   sleep 10 && \
   ${OCTOPUS} $O_params run 'hostname' 2>&1"

echo -n "Installing dependencies. This could take a while ... "
# install deps (not all are deps; some just make life easier debugging)
suppress_output_unless_error "${OCTOPUS} $O_params run \
  'zypper --non-interactive --gpg-auto-import-keys \
    install -y \
      bash-completion \
      ca-certificates \
      conntrack-tools \
      curl \
      docker \
      ebtables \
      ethtool \
      lvm2 \
      lsof \
      ntp \
      socat \
      tree \
      vim \
      wget \
      xfsprogs \
  '"
echo "done."

echo -n "Updating kernel. This can also take a little while ... "
# kernel-default has ipvs kernel modules
suppress_output_unless_error "${OCTOPUS} $O_params run \
  'zypper --non-interactive --gpg-auto-import-keys \
    install --allow-downgrade --force-resolution -y \
      kernel-default \
  '"
echo "done."

echo -n "Removing anti-dependencies ... "
suppress_output_unless_error "${OCTOPUS} $O_params run \
  'zypper --non-interactive --gpg-auto-import-keys \
    remove -y \
      firewalld \
  ' || true"
  # '|| true' b/c this fails if anti-deps already removed and is unlikely to fail otherwise
echo "done."

echo -n "Enabling docker ..."
# enable and start docker service
suppress_output_unless_error "${OCTOPUS} $O_params run 'systemctl enable --now docker'"
echo "done."

echo -n "Raising max open files ..."
suppress_output_unless_error "${OCTOPUS} $O_params run 'sysctl -w fs.file-max=1200000'"
echo "done."

echo -n "Minimize swappiness ..."
suppress_output_unless_error "${OCTOPUS} $O_params run 'sysctl -w vm.swappiness=0'"
echo "done."

echo "Rebooting nodes ..."
${OCTOPUS} $O_params run reboot &>/dev/null || true # will fail b/c conn will be lost

wait_for "new node to be up and ready" 90 \
  "${OCTOPUS} $O_params run 'hostname' 2>&1 && \
   sleep 10 && \
   ${OCTOPUS} $O_params run 'hostname' 2>&1"


echo -n "Setting iptables on nodes to be permissive ... "

suppress_output_unless_error "${OCTOPUS} $O_params run \
  'iptables -I INPUT -j ACCEPT && iptables -P INPUT ACCEPT'"

echo "done."


echo "Installing kubeadm components ..."


echo "  starting required IPVS kernel modules ..."
# required for k8s to use the "IPVS proxier"
suppress_output_unless_error "${OCTOPUS} $O_params run \
    'modprobe ip_vs ; modprobe ip_vs_rr ; modprobe ip_vs_wrr ; modprobe ip_vs_sh'"


echo "  downloading and installing crictl ..."
# kubeadm uses crictl to talk to docker/crio
CRICTL_VERSION=v1.14.0
K8S_VERSION=v1.15.2
suppress_output_unless_error "${OCTOPUS} $O_params run '\
    rm -f crictl-${CRICTL_VERSION}-linux-amd64.tar.gz*
    wget https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VERSION}/crictl-${CRICTL_VERSION}-linux-amd64.tar.gz && \
    tar -C /usr/bin -xf crictl-${CRICTL_VERSION}-linux-amd64.tar.gz && \
    chmod +x /usr/bin/crictl && \
    rm crictl-${CRICTL_VERSION}-linux-amd64.tar.gz'"

echo "  downloading and installing kubeadm binaries ..."
for binary in kubeadm kubectl kubelet; do
    suppress_output_unless_error "${OCTOPUS} $O_params run '\
        curl -LO https://storage.googleapis.com/kubernetes-release/release/${K8S_VERSION}/bin/linux/amd64/${binary} && \
        chmod +x ${binary} && mv ${binary} /usr/bin'"
done

echo "  downloading and installing CNI plugins ..."
# CNI plugins are required for most network addons
# https://github.com/containernetworking/plugins/releases
CNI_VERSION=v0.7.5
suppress_output_unless_error "${OCTOPUS} $O_params run '\
    rm -f cni-plugins-amd64-${CNI_VERSION}.tgz*
    wget https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-amd64-${CNI_VERSION}.tgz && \
    mkdir -p /opt/cni/bin && \
    tar -C /opt/cni/bin -xf cni-plugins-amd64-${CNI_VERSION}.tgz && \
    rm cni-plugins-amd64-${CNI_VERSION}.tgz'"

echo "  setting up kubelet service ..."
suppress_output_unless_error \
    "${OCTOPUS} $O_params copy $DEV_ROOK_CEPH/scripts/kubernetes/kubelet.service /usr/lib/systemd/system"
suppress_output_unless_error \
    "${OCTOPUS} $O_params run 'systemctl enable kubelet'"

echo "  disabling apparmor ..."
suppress_output_unless_error \
    "${OCTOPUS} $O_params run 'systemctl disable apparmor --now || true'"

echo "... done."



kube_setup_dir="/root/.setup-kube"

echo "Installing Kubernetes ${K8S_VERSION} ..."

echo "  copying config files to cluster ..."
suppress_output_unless_error \
  "${OCTOPUS} $O_params copy $DEV_ROOK_CEPH/scripts/kubernetes/KUBELET_EXTRA_ARGS /root"

echo "... done."

echo "  joining worker node to Kubernetes cluster ..."

pushd $DEV_ROOK_CEPH
    join_command="$(${OCTOPUS} --host-groups first_master run \
                    'kubeadm token create --print-join-command' | grep 'kubeadm join')"
popd

echo "Join command: "
echo $join_command

# for idempotency, do not run init if docker is already running kube resources
suppress_output_unless_error "${OCTOPUS} $O_params run \
  'if ! docker ps -a | grep -q kube; then ${join_command} ; fi'"


pushd $DEV_ROOK_CEPH
    kubectl --kubeconfig kubeconfig apply -f .rook-config/ceph/cluster.yaml
popd


# TODO(jhesketh): Do some verification of OSD


# TODO(jhesketh): Remove extra node to reset environment