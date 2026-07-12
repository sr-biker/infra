#!/bin/bash
set -euxo pipefail

KUBERNETES_VERSION="${kubernetes_version}"
JOIN_PARAM_NAME="${join_param_name}"
POD_CIDR="192.168.0.0/16"

# --- SELinux: permissive, same tradeoff most kubeadm-on-AL guides make rather than
# authoring full SELinux policies for kubelet/containerd/CNI ---
setenforce 0 || true
sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

# --- container runtime + kubeadm/kubelet/kubectl ---
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

# --- IMDS: this AMI/account enforces IMDSv2 (token required) — token-less curl to any
# 169.254.169.254 path returns 401, not a normal 200 with data. A prior Ubuntu-based
# version of this script assumed token-less IMDSv1 worked and silently got empty values
# for both PRIVATE_IP and REGION below.
IMDS_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
imds() {
  curl -s -H "X-aws-ec2-metadata-token: $${IMDS_TOKEN}" "http://169.254.169.254/latest/$${1}"
}

# --- bootstrap control plane ---
PRIVATE_IP=$(imds meta-data/local-ipv4)

kubeadm init \
  --pod-network-cidr="$${POD_CIDR}" \
  --apiserver-advertise-address="$${PRIVATE_IP}"

mkdir -p /root/.kube
cp -i /etc/kubernetes/admin.conf /root/.kube/config

export KUBECONFIG=/root/.kube/config
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml

# --- helm + Secrets Store CSI driver (AWS provider) ---
# Combined chart (the AWS provider chart bundles the driver as a sub-chart dependency) --
# installing them as two separate helm releases fails with an ownership conflict on the
# shared "secrets-store-csi-driver" ServiceAccount.
curl -fsSL -o /tmp/get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod +x /tmp/get_helm.sh
/tmp/get_helm.sh
helm repo add aws-secrets-manager https://aws.github.io/secrets-store-csi-driver-provider-aws
helm repo update
helm upgrade --install secrets-provider-aws aws-secrets-manager/secrets-store-csi-driver-provider-aws   --namespace kube-system   --set secrets-store-csi-driver.syncSecret.enabled=true

# --- publish join command for workers via SSM Parameter Store ---
# AL2023 ships aws-cli v2 and amazon-ssm-agent preinstalled/enabled — no package install
# needed for either, unlike the prior Ubuntu-based script.
REGION=$(imds meta-data/placement/region)
JOIN_COMMAND=$(kubeadm token create --print-join-command)

aws ssm put-parameter \
  --name "$${JOIN_PARAM_NAME}" \
  --type "SecureString" \
  --value "$${JOIN_COMMAND}" \
  --overwrite \
  --region "$${REGION}"
