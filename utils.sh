create_dirs() {
  mkdir -p $DIR/sandbox/bin
  mkdir -p $DIR/sandbox/configs
  export PATH=$DIR/sandbox/bin:$PATH
  cp -r $DIR/infra $DIR/apigw $DIR/svc $DIR/sandbox/
  cd $DIR/sandbox
}

get_namespaces() {
  echo $($DIR/sandbox/bin/yq r $DIR/values.yaml 'namespaces[*].name' | cut -d ' ' -f2)
}

get_services() {
  echo $($DIR/sandbox/bin/yq r $DIR/values.yaml "namespaces[$1].services[*].name" | cut -d ' ' -f2)
}

get_cluster() {
  cluster=$($DIR/sandbox/bin/yq r $DIR/values.yaml cluster)
  if [ "$cluster" == "null" ]; then cluster=$($DIR/sandbox/bin/yq r $DIR/values.yaml namespaces[0].name); fi
  echo $cluster
}

setup_gateway() {
  cluster=$(get_cluster)
  $DIR/sandbox/bin/yq w -i -d0 apigw/resources.yaml metadata.name $cluster-gateway
  $DIR/sandbox/bin/yq w -i -d1 apigw/resources.yaml metadata.name $cluster
  $DIR/sandbox/bin/yq w -i -d1 apigw/resources.yaml "spec.gateways[0]" $cluster-gateway
}

download_tools() {
  if [ ! -f ./bin/kind > /dev/null 2>&1 ]; then
    curl -Lo ./bin/kind https://github.com/kubernetes-sigs/kind/releases/download/v0.6.0/kind-$(uname)-amd64
    chmod +x ./bin/kind
  fi
  if [ ! -f ./bin/yq > /dev/null 2>&1 ]; then
    curl -Lo ./bin/yq https://github.com/mikefarah/yq/releases/download/2.4.1/yq_linux_amd64
    chmod +x ./bin/yq
  fi
  if [ ! -f ./bin/istioctl > /dev/null 2>&1 ]; then
    curl -L https://istio.io/downloadIstio | sh -
    ln -s ../istio-1.4.2/bin/istioctl bin/istioctl
  fi
}

setup_svcs() {
  if [ ! -d mockserver > /dev/null 2>&1 ]; then
    git clone https://github.com/mock-server/mockserver.git
    cd mockserver
    git checkout tags/mockserver-5.8.0
    sed -i 's|{{ .Values.image.repository }}/mockserver:mockserver-{{- if .Values.image.snapshot }}snapshot{{- else }}{{ .Chart.Version }}{{- end }}|williamyeh/json-server:1.1.1|' helm/mockserver/templates/deployment.yaml
    sed -i 's|imagePullPolicy: Always|command: ["json-server", "/config/db.json", "--host", "0.0.0.0", "--routes", "/config/routes.json"]|' helm/mockserver/templates/deployment.yaml
    sed -i 's|mockserver.properties|db.json|' helm/mockserver-config/templates/configmap.yaml
    sed -i 's|initializerJson.json|routes.json|' helm/mockserver-config/templates/configmap.yaml
    cd ..
  fi
  cd mockserver
  sed -i 's|mockserver.properties|db.json|' helm/mockserver-config/templates/configmap.yaml
  sed -i 's|initializerJson.json|routes.json|' helm/mockserver-config/templates/configmap.yaml
  nc=0
  routeRule=$($DIR/sandbox/bin/yq r -d1 ../apigw/resources.yaml spec.http | sed -e 's/^/  /')
  for ns in $(get_namespaces); do 
    ss=0
    for sc in $(get_services $nc); do 
      if [ "$ss" == "0" ]; then
        sed -i "s/svc/$sc/" ../apigw/resources.yaml
      fi
      i=$ns-$sc
      rm -rf helm/$i-config
      cp -r helm/mockserver-config helm/$i-config
      sed -i 's/name: mockserver-config/name: '$i'-configmap/' helm/$i-config/Chart.yaml
      cp -r $DIR/svc/mock/* helm/$i-config/static/
      cp -r $DIR/svc/mock/* helm/$i-config/static/
      cp $DIR/svc/values.yaml helm/$i-config/
      if [ "$ss" != "0" ]; then
        echo "$routeRule" | sed -e "s/svc/$sc/" >> ../apigw/resources.yaml
      fi
      $DIR/sandbox/bin/yq w -i helm/$i-config/values.yaml nameOverride $sc
      $DIR/sandbox/bin/yq w -i helm/$i-config/values.yaml app.mountedConfigMapName $i-configmap
      $DIR/sandbox/bin/yq w -i helm/$i-config/values.yaml ingress.enabled "false"
      $DIR/sandbox/bin/yq m -i helm/$i-config/values.yaml $DIR/values.yaml
      ss=$[$ss +1]
    done
    nc=$[$nc +1]
  done
  cd ..
}
