#!/bin/bash
set -euxo pipefail

KUBERNETES_VERSION="${kubernetes_version}"
JOIN_PARAM_NAME="${join_param_name}"

# --- SELinux: permissive, same tradeoff most kubeadm-on-AL guides make rather than
# authoring full SELinux policies for kubelet/containerd/CNI ---
setenforce 0 || true
sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

dnf install -y containerd

mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

cat <<REPO | tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v$${KUBERNETES_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v$${KUBERNETES_VERSION}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
REPO

dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
systemctl enable kubelet

swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

cat <<SYSCTL | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
SYSCTL
sysctl --system

# AL2023 ships aws-cli v2 preinstalled — no package install needed for it, unlike the
# prior Ubuntu-based script.
REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | grep region | cut -d '"' -f4)

# control plane writes the join command shortly after boot; poll until it's available
for i in $(seq 1 30); do
  JOIN_COMMAND=$(aws ssm get-parameter \
    --name "$${JOIN_PARAM_NAME}" \
    --with-decryption \
    --region "$${REGION}" \
    --query "Parameter.Value" \
    --output text) && break
  sleep 20
done

eval "$${JOIN_COMMAND}"
