set -e
PRV_DIR=$(pwd)
DIR="$(cd `dirname $0` && pwd)"

source $DIR/utils.sh

pre_clean() {
  create_dirs
  download_tools
}

clean_cluster() {
  cluster=$(get_cluster)
  if $DIR/sandbox/bin/kind get clusters | grep $cluster; then
    kind delete cluster --name $cluster --kubeconfig $DIR/sandbox/configs/$cluster
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  pre_clean
  clean_cluster
fi

cd $PRV_DIR
