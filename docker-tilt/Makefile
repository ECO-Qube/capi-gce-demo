.EXPORT_ALL_VARIABLES:
CAPI_KIND_CLUSTER_NAME = ecoqube-mgmt-dev
CAPI_WKLD_CLUSTER_NAME = ecoqube-wkld-dev
KIND_CLUSTER_VERSION = v1.27.1
CLUSTER_TOPOLOGY = true
EXP_CLUSTER_RESOURCE_SET = true
CURDIR = $(shell pwd)

.PHONY: all $(MAKECMDGOALS)

all: tilt-prepare tilt-management-up

tilt-prepare:
	unset KUBECONFIG && ./hack/kind-install-for-capd.sh

tilt-management-up: tilt-prepare
	kubectl config set-context kind-ecoqube-mgmt-dev-admin@kind-ecoqube-mgmt-dev && tilt up --file=management.tiltfile --port="10350"

tilt-workload-up:
	export KUBECONFIG="${CURDIR}/${CAPI_WKLD_CLUSTER_NAME}.kubeconfig" && \
	kubectl config set-context ${CAPI_WKLD_CLUSTER_NAME}-admin@${CAPI_WKLD_CLUSTER_NAME} && \
	cd tilt-workload && \
	tilt up --file=workload.tiltfile --port="10351"

clean:
	kind delete cluster --name=${CAPI_KIND_CLUSTER_NAME}
	kind delete cluster --name=${CAPI_WKLD_CLUSTER_NAME}
	docker ps --filter name="kind-registry" -aq | xargs docker stop | xargs docker rm
	unset KUBECONFIG
	kubectl config unset clusters.kind-${CAPI_KIND_CLUSTER_NAME}
	kubectl config unset users.kind-${CAPI_KIND_CLUSTER_NAME}
	kubectl config unset contexts.kind-${CAPI_KIND_CLUSTER_NAME}-admin@kind-${CAPI_KIND_CLUSTER_NAME}
