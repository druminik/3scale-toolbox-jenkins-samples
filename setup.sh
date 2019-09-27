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

# install jenkins and pipeline
oc new-app -n "$NAMESPACE" --template=jenkins-ephemeral --name=jenkins
oc set env -n "${NAMESPACE}" dc/jenkins JENKINS_OPTS=--sessionTimeout=86400

oc apply -f simple-setup/setup.yaml
