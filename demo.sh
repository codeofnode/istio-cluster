set -e
PRV_DIR=$(pwd)
DIR="$(cd `dirname $0` && pwd)"
source $DIR/setup.sh

export_urls() {
  HOST=$(kubectl get nodes -n apigw -o jsonpath='{.items[0].status.addresses[0].address}')
  PORT=$(kubectl get svc -n apigw apigw-kong-proxy -o jsonpath='{.spec.ports[1].nodePort}')
  APORT=$(kubectl get svc -n apigw apigw-kong-admin -o jsonpath='{.spec.ports[0].nodePort}')
  export PU=https://$HOST:$PORT
  export AU=https://$HOST:$APORT
  echo "Waiting for apigw to up and running ..."
  while [ "$(curl -s -o /dev/null -w "%{http_code}" -k $PU)" != "404" ]; do sleep 5; done
  echo "APIGW is up and running ..."
  echo "PROXY_URL=$PU"
  echo $(kubectl get secret -n infra grafana -o 'jsonpath={.data.admin-password}') | base64 --decode | xclip -selection c
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  bash -x $DIR/clean.sh
  bash -x $DIR/setup.sh
  export_kubectl
  export_urls
  echo PROXY_URL = $PU
  bash $DIR/traffic.sh $PU
fi

cd $DIR
