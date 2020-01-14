set -e
PRV_DIR=$(pwd)
DIR="$(cd `dirname $0` && pwd)"
source $DIR/setup.sh

kuma_urls() {
  echo "Skipping ..."
}

istio_urls() {
  export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')
  export SECURE_INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')
  export INGRESS_HOST=$(kubectl get po -l istio=ingressgateway -n istio-system -o jsonpath='{.items[0].status.hostIP}')
  export PU=https://$INGRESS_HOST:$SECURE_INGRESS_PORT
  echo "Waiting for services to up and running ..."
  while [ "$(curl -s -o /dev/null -w "%{http_code}" -k $PU)" != "404" ]; do sleep 5; done
  echo "Serivces is up and running ..."
  echo "PROXY_URL=$PU"
}

kong_urls() {
  HOST=$(kubectl get nodes -n apigw -o jsonpath='{.items[0].status.addresses[0].address}')
  PORT=$(kubectl get svc -n apigw apigw-kong-proxy -o jsonpath='{.spec.ports[1].nodePort}')
  APORT=$(kubectl get svc -n apigw apigw-kong-admin -o jsonpath='{.spec.ports[0].nodePort}')
  export PU=https://$HOST:$PORT
  export AU=https://$HOST:$APORT
  echo "Waiting for services to up and running ..."
  while [ "$(curl -s -o /dev/null -w "%{http_code}" -k $PU)" != "404" ]; do sleep 5; done
  echo "Serivces is up and running ..."
  echo "PROXY_URL=$PU"
  echo $(kubectl get secret -n infra grafana -o 'jsonpath={.data.admin-password}') | base64 --decode | xclip -selection c
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  bash -x $DIR/clean.sh
  bash -x $DIR/setup.sh $1
  export_kubectl
  ${1:-istio}_urls
  echo PROXY_URL = $PU
  bash $DIR/traffic.sh $PU
fi

cd $DIR
