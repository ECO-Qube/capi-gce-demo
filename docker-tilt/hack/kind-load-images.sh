#!/usr/bin/env bash

docker pull calico/kube-controllers:v3.23.3 &
docker pull calico/node:v3.23.3 &
docker pull calico/cni:v3.23.3 &
docker pull directxman12/k8s-prometheus-adapter-amd64:latest &
docker pull prom/node-exporter &
docker pull prom/prometheus:v2.2.1 &
docker pull cristianohelio/target-exporter:0.0.8 # TODO: Still needed if we build images locally? &
wait

kind load docker-image docker.io/calico/kube-controllers:v3.23.3 --name $CAPI_WKLD_CLUSTER_NAME &
kind load docker-image docker.io/calico/node:v3.23.3 --name $CAPI_WKLD_CLUSTER_NAME &
kind load docker-image docker.io/calico/cni:v3.23.3 --name $CAPI_WKLD_CLUSTER_NAME &
kind load docker-image docker.io/directxman12/k8s-prometheus-adapter-amd64:latest --name $CAPI_WKLD_CLUSTER_NAME &
kind load docker-image docker.io/prom/node-exporter --name $CAPI_WKLD_CLUSTER_NAME &
kind load docker-image docker.io/prom/prometheus:v2.2.1 --name $CAPI_WKLD_CLUSTER_NAME &
kind load docker-image docker.io/cristianohelio/target-exporter:0.0.8 --name $CAPI_WKLD_CLUSTER_NAME &
wait