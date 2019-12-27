set -e
PRV_DIR=$(pwd)
DIR="$(cd `dirname $0` && pwd)"

source $DIR/utils.sh

pre_setup() {
  create_dirs
  download_tools
  setup_svcs
}

cluster_setup() {
  cluster=$(get_cluster)
  rm -f $DIR/sandbox/configs/$cluster
  if ! $DIR/sandbox/bin/kind get clusters | grep $cluster; then
    $DIR/sandbox/bin/kind create cluster --name $cluster --kubeconfig $DIR/sandbox/configs/$cluster
  fi
  if command -v kctl > /dev/null 2>&1; then
    kctl ln local $DIR/sandbox/configs/$cluster
    source kctl
  else
    export KUBECONFIG=$DIR/sandbox/configs/$cluster
  fi
  kubectl create ns apigw 
  for ns in $(get_namespaces); do
    kubectl create ns $ns
  done
  kubectl create ns infra
}

apigw_setup() {
  export IP=$(ip -o -4 a | tail -1 | awk '{print $4 }' | sed -e 's/\/.*$//')
  if [ "$IP" == "" ]; then IP=172.17.0.1; fi
  helm install apigw stable/kong --namespace apigw -f apigw/values.yaml --set proxy.externalIPs[0]=$IP
}

infra_setup() {
  helm install prometheus stable/prometheus --namespace infra -f infra/prometheus/values.yaml
  helm install grafana stable/grafana --namespace infra --values http://bit.ly/2FuFVfV
}

plugins_setup() {
  for ns in $(get_namespaces); do 
    yq w -d'*' apigw/resources.yaml metadata.namespace $ns | kubectl apply -f -
  done
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
  POD_NAME=$(kubectl get pods -n infra -l "app=prometheus,component=server" -o jsonpath="{.items[0].metadata.name}")
  wait_for_pod infra $POD_NAME
  kubectl -n infra port-forward $POD_NAME 9090 &
  POD_NAME=$(kubectl get pods --namespace infra -l "app=grafana" -o jsonpath="{.items[0].metadata.name}")
  wait_for_pod infra $POD_NAME
  kubectl -n infra port-forward $POD_NAME 3000 &
  POD_NAME=$(kubectl get pods --namespace apigw -l "app=kong" -o jsonpath="{.items[0].metadata.name}")
  wait_for_pod apigw $POD_NAME
  kubectl -n apigw port-forward $POD_NAME 8000 &
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
  apigw_setup
  plugins_setup
  svc_setup
  port_forwards
fi

cd $PRV_DIR
