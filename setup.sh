set -e
PRV_DIR=$(pwd)
DIR="$(cd `dirname $0` && pwd)"

source $DIR/utils.sh
cluster=$(get_cluster)

pre_setup() {
  create_dirs
  setup_gateway
  download_tools
  setup_svcs
}

export_kubectl() {
  if command -v kctl > /dev/null 2>&1; then
    kctl ln local $DIR/sandbox/configs/$cluster
    source kctl
  else
    export KUBECONFIG=$DIR/sandbox/configs/$cluster
  fi
}

cluster_setup() {
  rm -f $DIR/sandbox/configs/$cluster
  if ! $DIR/sandbox/bin/kind get clusters | grep $cluster; then
    $DIR/sandbox/bin/kind create cluster --name $cluster --kubeconfig $DIR/sandbox/configs/$cluster
  fi
  export_kubectl
  for ns in $(get_namespaces); do
    kubectl create ns $ns
    kubectl label namespace $ns istio-injection=enabled
  done
}

infra_setup() {
  $DIR/sandbox/bin/istioctl manifest apply --set profile=demo
}

wait_for_pod() {
  echo "waiting for pod ..."
  while [[ $(kubectl get pods -n $1 $2 -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do
    sleep 5
  done
}

port_forwards() {
  killall kubectl || true
  sleep 3
  POD_NAME=$(kubectl -n istio-system get pod -l app=grafana -o jsonpath='{.items[0].metadata.name}')
  wait_for_pod istio-system $POD_NAME
  kubectl -n infra port-forward $POD_NAME 3000 &
}

svc_setup() {
  nc=0
  for ns in $(get_namespaces); do 
    for sc in $(get_services $nc); do 
      helm install $ns-$sc ./mockserver/helm/mockserver --namespace $ns -f ./mockserver/helm/$ns-$sc-config/values.yaml
      helm install $ns-$sc-config ./mockserver/helm/$ns-$sc-config --namespace $ns
    done
    nc=$[$nc +1]
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  pre_setup
  cluster_setup
  infra_setup
  svc_setup
  port_forwards
fi

cd $PRV_DIR
