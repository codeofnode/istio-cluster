set -e
PRV_DIR=$(pwd)
DIR="$(cd `dirname $0` && pwd)"
source $DIR/setup.sh

export_urls() {
  export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')
  export SECURE_INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')
  export INGRESS_HOST=$(kubectl get po -l istio=ingressgateway -n istio-system -o jsonpath='{.items[0].status.hostIP}')
  export PU=https://$INGRESS_HOST:$SECURE_INGRESS_PORT
  echo "Waiting for services to up and running ..."
  while [ "$(curl -s -o /dev/null -w "%{http_code}" -k $PU)" != "404" ]; do sleep 5; done
  echo "Serivces is up and running ..."
  echo "PROXY_URL=$PU"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  bash -x $DIR/clean.sh
  bash -x $DIR/setup.sh
  export_kubectl
  export_urls
  echo PROXY_URL = $PU
exit
  bash $DIR/traffic.sh $PU
fi

cd $DIR
