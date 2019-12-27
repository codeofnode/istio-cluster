set -e
PRV_DIR=$(pwd)
DIR="$(cd `dirname $0` && pwd)"

source $DIR/utils.sh

generate() {
  echo "Waiting for services ..."
  while [ "$(curl -s -o /dev/null -w "%{http_code}" -k $1)" == "000" ]; do sleep 3; done
  echo "Taffic being bombarded ..."
  google-chrome http://localhost:3000
  while true;
  do
    nc=0
    for ns in $(get_namespaces); do 
      for sc in $(get_services $nc); do 
        curl -sk $1/$sc/healthz
        curl -sk $1/healthz
        curl -sk -X POST $1/$sc/user -d a=1
        curl -sk -X POST $1/user -d a=1
        curl -sk $1/$sc/user
        curl -sk $1/user
        curl -sk $1/xyz/api/v1
        curl -sk $1/$sc/users
        curl -sk $1/users
        curl -sk $1
      done
      nc=$[$nc +1]
    done
    sleep 0.1
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  generate "$@"
fi

cd $PRV_DIR
