#!/bin/bash
set -euxo pipefail

KUBERNETES_VERSION="${kubernetes_version}"
JOIN_PARAM_NAME="${join_param_name}"

apt-get update
apt-get install -y apt-transport-https ca-certificates curl gpg awscli containerd

mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

curl -fsSL "https://pkgs.k8s.io/core:/stable:/v$${KUBERNETES_VERSION}/deb/Release.key" | \
  gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v$${KUBERNETES_VERSION}/deb/ /" | \
  tee /etc/apt/sources.list.d/kubernetes.list

apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

cat <<SYSCTL | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
SYSCTL
sysctl --system

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
