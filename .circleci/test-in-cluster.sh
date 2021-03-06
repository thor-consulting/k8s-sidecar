#!/usr/bin/env bash
#
# install sidecar in kubernetes kind
#

set -o errexit
set -o pipefail
set -o nounset;

REPO_ROOT="$(git rev-parse --show-toplevel)"
WORKDIR="/workdir"
CLUSTER_NAME="sidecar-testing"
BIN_DIR="$(mktemp -d)"
KIND="${BIN_DIR}/kind"

#if [ -n "${CIRCLE_PULL_REQUEST}" ]; then
  echo -e "\\nTesting in Kubernetes ${K8S_VERSION}\\n"

  install_kubectl(){
    echo 'Installing kubectl...'
    curl -LO https://storage.googleapis.com/kubernetes-release/release/`curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt`/bin/linux/amd64/kubectl
    chmod +x ./kubectl
    sudo mv ./kubectl /usr/local/bin/kubectl
  }

  install_kind_release() {
    echo 'Installing kind...'

    KIND_BINARY_URL="https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-amd64"
    wget -O "${KIND}" "${KIND_BINARY_URL}"
    chmod +x "${KIND}"
  }

  create_kind_cluster() {

      "${KIND}" create cluster --loglevel=debug --config "${REPO_ROOT}"/.circleci/kind-config.yaml --image "kindest/node:${K8S_VERSION}"
      #kind create cluster --name "${CLUSTER_NAME}" --config "${REPO_ROOT}"/.circleci/kind-config.yaml --image "kindest/node:${K8S_VERSION}"

      KUBECONFIG="$("${KIND}" get kubeconfig-path)"
      export KUBECONFIG
      #export KUBECONFIG="$(kind get kubeconfig-path --name="${CLUSTER_NAME}")"
      
      kubectl cluster-info
      echo

      echo -n 'Waiting for cluster to be ready...'
      until ! grep --quiet 'NotReady' <(kubectl get nodes --no-headers); do
          printf '.'
          sleep 1
      done

      echo '✔︎'
      echo

      kubectl get nodes
      echo

      echo 'Cluster ready!'
      echo
  }

  install_sidecar(){
    kubectl apply -f "${REPO_ROOT}"/.circleci/test/sidecar.yaml
  }

  install_configmap(){
    kubectl apply -f "${REPO_ROOT}"/.circleci/test/configmap.yaml
  }

  list_pods(){
    kubectl get pods -oyaml
  }


  log_sidecar(){
    kubectl logs sidecar
  }

  verify_configmap_read(){
    kubectl exec sidecar -- ls /tmp/hello.world
    kubectl exec sidecar -- ls /tmp/hello.binary
  }

  cleanup_cluster() {
    if [ -n "$(command -v kind)" ]; then
      for CLUSTER in $(kind get clusters); do
        echo "delete old cluster ${CLUSTER}"
        kind delete cluster --name "${CLUSTER}"
      done
    fi
  }

  # cleanup on exit (useful for running locally)
  cleanup() {
    "${KIND}" delete cluster || true
    rm -rf "${BIN_DIR}"
  }
  trap cleanup EXIT

  main() {
      install_kubectl
      #cleanup_cluster
      install_kind_release
      create_kind_cluster
      install_sidecar
      sleep 5
      install_configmap
      sleep 10
      list_pods
      log_sidecar
      verify_configmap_read
  }
  main

#else
#  echo "skipped sidecar test as its not a pull request..."
#fi
