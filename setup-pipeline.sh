#!/bin/bash
#############
# LOGIN
#############
oc login -u admin
oc project 3scale-26

#############
# SETUP
#############

# Save the generated access token for later use. For example:
export SAAS_ACCESS_TOKEN=075fba0b1614b44abd00a0288c7b5a0ab7bc52582d0e3947a7b1286b82def3aa
# Save the name of your 3scale tenant for later use:
#export ONPREM_ADMIN_PORTAL_HOSTNAME="$(oc get route system-provider-admin -o jsonpath='{.spec.host}')"
export ONPREM_ADMIN_PORTAL_HOSTNAME="$(oc get route zync-3scale-provider-q86rv -o jsonpath='{.spec.host}')"
# Define your wildcard routes:
export OPENSHIFT_ROUTER_SUFFIX=ch-3scale-devl.apps.helvetia.io  # Replace me!
export APICAST_ONPREM_STAGING_WILDCARD_DOMAIN=3scale-apicast-staging.$OPENSHIFT_ROUTER_SUFFIX
export APICAST_ONPREM_PRODUCTION_WILDCARD_DOMAIN=3scale-apicast-production.$OPENSHIFT_ROUTER_SUFFIX

# Add the wildcard routes to your existing 3scale on-premises instance:
oc create route edge apicast-wildcard-staging --service=apicast-staging --hostname="wildcard.$APICAST_ONPREM_STAGING_WILDCARD_DOMAIN" --insecure-policy=Allow --wildcard-policy=Subdomain
oc create route edge apicast-wildcard-production --service=apicast-production --hostname="wildcard.$APICAST_ONPREM_PRODUCTION_WILDCARD_DOMAIN" --insecure-policy=Allow --wildcard-policy=Subdomain

# Define DEveloper Account for deploying APIs
export ONPREM_DEVELOPER_ACCOUNT_ID=3

#############
# INSTALL RH SSO
#############
oc replace -n openshift --force -f https://raw.githubusercontent.com/jboss-container-images/redhat-sso-7-openshift-image/sso73-dev/templates/sso73-image-stream.json
oc replace -n openshift --force -f https://raw.githubusercontent.com/jboss-container-images/redhat-sso-7-openshift-image/sso73-dev/templates/sso73-x509-postgresql-persistent.json
oc -n openshift import-image redhat-sso73-openshift:1.0
oc policy add-role-to-user view system:serviceaccount:$(oc project -q):default
oc new-app --template=sso73-x509-postgresql-persistent --name=sso -p DB_USERNAME=sso -p SSO_ADMIN_USERNAME=admin -p DB_DATABASE=sso

export SSO_HOSTNAME="$(oc get route sso -o jsonpath='{.spec.host}')"

# Configure RH-SSO for 3scale as explained in the 3scale Developer Portal documentation.
export REALM=3scale
export CLIENT_ID=3scale-admin
export CLIENT_SECRET=123...456

 
############
# DEPLOY JENKINS ON OPENSHIFT
#############
#Save the name of the project for later use:
export TOOLBOX_NAMESPACE=api-lifecycle

# Create an OpenShift project for your artifacts:
oc new-project "$TOOLBOX_NAMESPACE"


#Deploy a Jenkins master:
#oc new-app -n "$TOOLBOX_NAMESPACE" --template=jenkins-ephemeral --name=jenkins -p MEMORY_LIMIT=2Gi
oc new-app -n "$TOOLBOX_NAMESPACE" --template=jenkins-ephemeral --name=jenkins
oc set env -n "$TOOLBOX_NAMESPACE" dc/jenkins JENKINS_OPTS=--sessionTimeout=86400

############
#INSTALL 3SCALE TOOLBOX
#############
# Install 3scale toolbox and generate a secret
3scale remote add 3scale-onprem "https://$ONPREM_ACCESS_TOKEN@$ONPREM_ADMIN_PORTAL_HOSTNAME/"

# Run the following OpenShift command to provision the secret containing your 3scale Admin Portal and access token:
oc create secret generic 3scale-toolbox -n "$TOOLBOX_NAMESPACE" --from-file="$HOME/.3scalerc.yaml"


############
# DEPLOY API BACKEND
#############
oc new-app -n "$TOOLBOX_NAMESPACE" -i openshift/redhat-openjdk18-openshift:1.4 https://github.com/microcks/api-lifecycle.git --context-dir=/beer-catalog-demo/api-implementation --name=beer-catalog
oc expose -n "$TOOLBOX_NAMESPACE" svc/beer-catalog

export BEER_CATALOG_HOSTNAME="$(oc get route -n "$TOOLBOX_NAMESPACE" beer-catalog -o jsonpath='{.spec.host}')"

# Deploy the sample Event API backend for use with the following samples:
oc new-app -n "$TOOLBOX_NAMESPACE" -i openshift/nodejs:10 'https://github.com/nmasse-itix/rhte-api.git#085b015' --name=event-api
oc expose -n "$TOOLBOX_NAMESPACE" svc/event-api

#Save the Event API host name for later use:
export EVENT_API_HOSTNAME="$(oc get route -n "$TOOLBOX_NAMESPACE" event-api -o jsonpath='{.spec.host}')"

############
# INSTALL PIPELINE
#############
oc process -f semver-usecase/setup.yaml \
           -p DEVELOPER_ACCOUNT_ID="$ONPREM_DEVELOPER_ACCOUNT_ID" \
           -p PRIVATE_BASE_URL="http://$EVENT_API_HOSTNAME" \
           -p PUBLIC_STAGING_WILDCARD_DOMAIN="$APICAST_ONPREM_STAGING_WILDCARD_DOMAIN" \
           -p PUBLIC_PRODUCTION_WILDCARD_DOMAIN="$APICAST_ONPREM_PRODUCTION_WILDCARD_DOMAIN" \
           -p OIDC_ISSUER_ENDPOINT="https://$CLIENT_ID:$CLIENT_SECRET@$SSO_HOSTNAME/auth/realms/$REALM" \
           -p NAMESPACE="$TOOLBOX_NAMESPACE" |oc create -f -


oc process -f saas-usecase-apikey/setup.yaml \
           -p DEVELOPER_ACCOUNT_ID="$ONPREM_DEVELOPER_ACCOUNT_ID" \
           -p PRIVATE_BASE_URL="http://$BEER_CATALOG_HOSTNAME" \
           -p NAMESPACE="$TOOLBOX_NAMESPACE" |oc create -f -





export TOOLBOX_NAMESPACE=api-lifecycle

# Deploy the sample Event API backend for use with the following samples:
oc new-app -n "$TOOLBOX_NAMESPACE" -i openshift/nodejs:10 'https://github.com/nmasse-itix/rhte-api.git#085b015' --name=event-api
oc expose -n "$TOOLBOX_NAMESPACE" svc/event-api

#Save the Event API host name for later use:
export EVENT_API_HOSTNAME="$(oc get route -n "$TOOLBOX_NAMESPACE" event-api -o jsonpath='{.spec.host}')"

oc process -f multi-environment-usecase/setup.yaml \
           -p DEVELOPER_ACCOUNT_ID="$ONPREM_DEVELOPER_ACCOUNT_ID" \
           -p PRIVATE_BASE_URL="http://$EVENT_API_HOSTNAME" \
           -p PUBLIC_STAGING_WILDCARD_DOMAIN="$APICAST_ONPREM_STAGING_WILDCARD_DOMAIN" \
           -p PUBLIC_PRODUCTION_WILDCARD_DOMAIN="$APICAST_ONPREM_PRODUCTION_WILDCARD_DOMAIN" \
           -p NAMESPACE="$TOOLBOX_NAMESPACE" |oc create -f -


