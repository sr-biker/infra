#!/bin/bash
set -euxo pipefail

KUBERNETES_VERSION="${kubernetes_version}"
JOIN_PARAM_NAME="${join_param_name}"
POD_CIDR="192.168.0.0/16"

# --- container runtime + kubeadm/kubelet/kubectl ---
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

# --- bootstrap control plane ---
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

kubeadm init \
  --pod-network-cidr="$${POD_CIDR}" \
  --apiserver-advertise-address="$${PRIVATE_IP}"

mkdir -p /root/.kube
cp -i /etc/kubernetes/admin.conf /root/.kube/config

export KUBECONFIG=/root/.kube/config
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml

# --- publish join command for workers via SSM Parameter Store ---
REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | grep region | cut -d '"' -f4)
JOIN_COMMAND=$(kubeadm token create --print-join-command)

aws ssm put-parameter \
  --name "$${JOIN_PARAM_NAME}" \
  --type "SecureString" \
  --value "$${JOIN_COMMAND}" \
  --overwrite \
  --region "$${REGION}"
