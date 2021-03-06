#!/bin/bash
# Usage: ./knoweng.sh [hostname]
#
# This script will deploy the KnowEnG platform as a series of Kubernetes YAML.
#
# It assumes that you have a local kubectl binary installed in the
# location pointed to by $BINDIR
#
#

# Mode can be either 'dev' or 'prod'
MODE="dev"

# Location of "kubectl" binary
BINDIR="/usr/local/bin"
ECHO="echo -e"
DOMAIN="${1:-knowkube.ndslabs.org}"

# For development instances, start a single-node 
# Kubernetes cluster running under Docker
if [ "$MODE" == "dev" ]; then
    ./kube.sh
fi

# Make sure we've created a basic-auth secret
kube_output="$(kubectl get secret -o name basic-auth 2>&1)"
if [ "$kube_output" != "secret/basic-auth" ]; then
    echo "Generating new basic-auth secret... This will be used to authenticate into your Cloud9 IDE"

    # Collect Username
    read -p "Username: " username
    if [ ! -n "$username" ]; then
        $ECHO 'No username entered... Aborting'
        exit 1
    fi

    # Collect Password
    read -s -p "Password: " password
    if [ ! -n "$password" ]; then
        $ECHO 'No password entered... Aborting'
        exit 1
    fi
    $ECHO ""

    # Collect confirmation
    read -s -p "Confirm password: " password_confirm
    if [ ! -n "$password_confirm" -o "$password" != "$password_confirm" ]; then
        $ECHO 'Passwords did not match.'
        exit 1
    fi
    $ECHO ""

    # Build these credentials into a new secret called "basic-auth"
    auth="$(docker run -it --rm bodom0015/htpasswd -b -c /dev/stdout $username $password | tail -1)"
    $BINDIR/kubectl create secret generic basic-auth --from-literal=auth="$auth"
else
    $ECHO "basic-auth" secret already exists... reusing
fi

# Make sure that we have self-signed certs generated
CRT_DIR="certs"
if [ ! -f "${CRT_DIR}/${DOMAIN}.cert" ]; then
    $ECHO "\nGenerating self-signed certificate for $DOMAIN"
    mkdir -p ${CRT_DIR}
    if [ ! -f "${CRT_DIR}/${DOMAIN}.key" ]; then
        openssl genrsa 2048 > ${CRT_DIR}/${DOMAIN}.key
    else
        $ECHO "SSL keyfile already exists for ${DOMAIN}... reusing"
    fi
    openssl req -new -x509 -nodes -sha1 -days 3650 -subj "/C=US/ST=IL/L=Champaign/O=NCSA/OU=NDS/CN=$DOMAIN" -key "${CRT_DIR}/${DOMAIN}.key" -out "${CRT_DIR}/${DOMAIN}.cert"
else
    $ECHO "self-signed SSL certificates already exist for ${DOMAIN}... reusing"
fi

# Make sure our TLS certs have been loaded as secrets
$BINDIR/kubectl create secret generic nest-tls-secret --from-file=tls.crt="${CRT_DIR}/${DOMAIN}.cert" --from-file=tls.key="${CRT_DIR}/${DOMAIN}.key" --namespace=kube-system
$BINDIR/kubectl create secret generic nest-tls-secret --from-file=tls.crt="${CRT_DIR}/${DOMAIN}.cert" --from-file=tls.key="${CRT_DIR}/${DOMAIN}.key"

# Always start the loadbalancer
$BINDIR/kubectl apply -f platform/loadbalancer.yaml

# Start nest dev / prod instance
$BINDIR/kubectl apply -f platform/nest.${MODE}.yaml

# If this is a developer instance, also start up Cloud9
if [ "$MODE" == "dev" ]; then
    $BINDIR/kubectl apply -f platform/cloud9.yaml
fi
