#!/bin/bash
minishift profile delete toolbox -f

minishift profile set toolbox
minishift config set memory 8GB
minishift config set cpus 4
minishift config set vm-driver virtualbox
minishift start

oc login -u system:admin
oc adm policy add-cluster-role-to-user cluster-admin admin
oc login -u admin
export NAMESPACE="toolbox"

oc login -u admin
oc new-project "${NAMESPACE}"

# INSTALL 3SCALE TOOLBOX
# Check version
ruby -v
# Install the Ruby Version Manager rvm
curl -L https://get.rvm.io | bash -s stable
rvm install ruby-2.4.1
rvm use ruby-2.4.1
rvm --default use 2.4.1
gem install 3scale_toolbox

#Generate the 3scale toolbox secret
#3scale remote add 3scale-saas "https://$SAAS_ACCESS_TOKEN@$SAAS_TENANT-admin.3scale.net/"
3scale remote add 3scale-onprem "https://$ONPREM_ACCESS_TOKEN@$ONPREM_ADMIN_PORTAL_HOSTNAME/"
oc create secret generic 3scale-toolbox -n "$NAMESPACE" --from-file="$HOME/.3scalerc.yaml"

# install jenkins and pipeline
oc new-app -n "$NAMESPACE" --template=jenkins-ephemeral --name=jenkins
oc set env -n "${NAMESPACE}" dc/jenkins JENKINS_OPTS=--sessionTimeout=86400
oc process -f simple-setup/setup.yaml -p DEVELOPER_ACCOUNT_ID=3 -p PRIVATE_BASE_URL="https://gugus" | oc apply -f - 
oc start-build simple-setup --follow

