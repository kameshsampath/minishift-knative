#!/bin/sh 

BINARY=build/bin/minishift
OPENSHIFT_VERSION="v3.11.0"
EXTRA_FLAGS="--skip-startup-checks"
ISTIO_URL='https://storage.googleapis.com/knative-releases/serving/latest/istio.yaml'
ISTIO_LATEST_URL='https://storage.googleapis.com/knative-releases/serving/latest/istio.yaml'
KNATIVE_SERVING_LATEST_URL='https://storage.googleapis.com/knative-releases/serving/latest/release-no-mon.yaml'
OC_VERSION="oc v3.11.0-alpha.0+0cbc58b-1286"

function print_success_message() {
  echo ""
  echo " ------------ [ $1 - Passed ]"
  echo ""
}

function exit_with_message() {
  if [[ "$1" != 0 ]]; then
    echo "$2"
    exit 1
  fi
}

function assert_equal() {
  if [ "$1" != "$2" ]; then
    echo "Expected '$2' but got '$1'"
    exit 1
  fi
}

function verify_istio_install(){
  # Grant the necessary privileges to the service accounts Istio will use:
  oc adm policy add-scc-to-user anyuid -z istio-ingress-service-account -n istio-system
  oc adm policy add-scc-to-user anyuid -z default -n istio-system
  oc adm policy add-scc-to-user anyuid -z prometheus -n istio-system
  oc adm policy add-scc-to-user anyuid -z istio-egressgateway-service-account -n istio-system
  oc adm policy add-scc-to-user anyuid -z istio-citadel-service-account -n istio-system
  oc adm policy add-scc-to-user anyuid -z istio-ingressgateway-service-account -n istio-system
  oc adm policy add-scc-to-user anyuid -z istio-cleanup-old-ca-service-account -n istio-system
  oc adm policy add-scc-to-user anyuid -z istio-mixer-post-install-account -n istio-system
  oc adm policy add-scc-to-user anyuid -z istio-mixer-service-account -n istio-system
  oc adm policy add-scc-to-user anyuid -z istio-pilot-service-account -n istio-system
  oc adm policy add-scc-to-user anyuid -z istio-sidecar-injector-service-account -n istio-system
  oc adm policy add-cluster-role-to-user cluster-admin -z istio-galley-service-account -n istio-system
  oc apply -f $ISTIO_URL
  # Ensure the istio-sidecar-injector pod runs as privileged
  oc get cm istio-sidecar-injector -n istio-system -o yaml | sed -e 's/securityContext:/securityContext:\\n      privileged: true/' | oc replace -f -
  # Monitor the Istio components until all of the components show a STATUS of Running or Completed:
  while oc get pods -n istio-system | grep -v -E "(Running|Completed|STATUS)"; do sleep 5; done
  print_success_message "Istio Installed successfully"
}

function verify_admission_webhooks(){
  minishift openshift config set --target=kube --patch '{
      "admissionConfig": {
          "pluginConfig": {
              "ValidatingAdmissionWebhook": {
                  "configuration": {
                      "apiVersion": "apiserver.config.k8s.io/v1alpha1",
                      "kind": "WebhookAdmission",
                      "kubeConfigFile": "/dev/null"
                  }
              },
              "MutatingAdmissionWebhook": {
                  "configuration": {
                      "apiVersion": "apiserver.config.k8s.io/v1alpha1",
                      "kind": "WebhookAdmission",
                      "kubeConfigFile": "/dev/null"
                  }
              }
          }
      }
  }'
  # Wait for the api servers to come up again 
  until oc login -u admin -p admin; do sleep 5; done;

  # set to default project 
  oc project myproject
  # 
  oc adm policy add-scc-to-user privileged -z default
  print_success_message "Admission Webhooks Configured successfully"
}

function verify_knative_install(){
  # Grant the necessary privileges to the service accounts Knative will use:
  oc adm policy add-scc-to-user anyuid -z build-controller -n knative-build
  oc adm policy add-scc-to-user anyuid -z controller -n knative-serving
  oc adm policy add-scc-to-user anyuid -z autoscaler -n knative-serving
  oc adm policy add-cluster-role-to-user cluster-admin -z build-controller -n knative-build
  oc adm policy add-cluster-role-to-user cluster-admin -z controller -n knative-serving
  oc apply -f $KNATIVE_SERVING_LATEST_URL
  while oc get pods -n knative-build | grep -v -E "(Running|Completed|STATUS)"; do sleep 5; done
  while oc get pods -n knative-serving | grep -v -E "(Running|Completed|STATUS)"; do sleep 5; done
  print_success_message "Knative Installed successfully"
}

function verify_sample_app(){
  # make sure you are in default project
  oc project myproject

  echo '
  apiVersion: serving.knative.dev/v1alpha1 # Current version of Knative
  kind: Service
  metadata:
    name: helloworld-go # The name of the app
  spec:
    runLatest:
      configuration:
        revisionTemplate:
          spec:
            container:
              image: gcr.io/knative-samples/helloworld-go # The URL to the image of the app
              env:
              - name: TARGET # The environment variable printed out by the sample app
                value: "Go Sample v1"
  ' | oc create -f -
  while oc get pods -n myproject | grep -v -E "(Running)"; do sleep 5; done
  IP_ADDRESS=$(minishift ip):$(oc get svc knative-ingressgateway -n istio-system -o 'jsonpath={.spec.ports[?(@.port==80)].nodePort}')
  curl -H "Host: helloworld-go.myproject.example.com" http://$IP_ADDRESS
}

function verify_oc(){
  output=`oc version | sed -n 1p`
  assert_equal "$output" "$OC_VERSION"
  print_success_message "openshift-cli version ${OC_VERSION} installed and configured correctly"
}

function verify_start_instance(){
  $BINARY profile set knative
  $BINARY addons enable admin-user
  $BINARY addons enable anyuid
  $BINARY config set memory 8GB
  $BINARY config set openshift-version v3.11.0
  $BINARY config set  cpus 4 
  $BINARY config set disk-size 50g
  $BINARY config set openshift-version ${OPENSHIFT_VERSION}
  $BINARY config set image-caching true
  $BINARY start $EXTRA_FLAGS
  exit_with_message "$?" "Error starting Minishift VM"
  output=`$BINARY status | sed -n 1p`
  assert_equal "$output" "Minishift:  Running"
  print_success_message "Started VM"
}

function verify_stop_instance() {
  $BINARY stop
  exit_with_message "$?" "Error starting Minishift VM"
  output=`$BINARY status | sed -n 1p`
  assert_equal "$output" "Minishift:  Stopped"
  print_success_message "Stopped VM"
}

function verify_ssh_connection() {
  output=`$BINARY ssh -- echo hello`
  assert_equal "$output" "hello"
  print_success_message "SSH Connection"
}

function verify_vm_ip() {
  output=`$BINARY ip`
  assert_valid_ip $output
  print_success_message "Getting VM IP"
}

function verify_delete() {
  $BINARY delete --force
  exit_with_message "$?" "Error deleting Minishift VM"
}

# Tests
verify_start_instance
# sleep 90

eval $($BINARY docker-env) && eval $($BINARY oc-env)
oc login -u admin -p admin 

# oc binary test
#verify_oc

# Istio Install test 
#verify_istio_install

# Admission Controller Check
verify_admission_webhooks

# Knative Install Test
verify_knative_install

# Deploy sample application
verify_sample_app

# Stop and Delete
verify_stop_instance
verify_delete
