.EXPORT_ALL_VARIABLES:
CAPI_KIND_CLUSTER_NAME = ecoqube-mgmt-dev
CAPI_WKLD_CLUSTER_NAME = ecoqube-wkld-dev
KIND_CLUSTER_VERSION = v1.27.3
CLUSTER_TOPOLOGY = true
EXP_CLUSTER_RESOURCE_SET = true
KIND_REGISTRY_NAME = kind-registry
KIND_REGISTRY_PORT = 5000
CURDIR = $(shell pwd)

.PHONY: all $(MAKECMDGOALS)

all: tilt-prepare-mgmt tilt-management-up

tilt-prepare-mgmt:
	unset KUBECONFIG && ./hack/kind-install-for-capd.sh

tilt-management-up: tilt-prepare-mgmt
	unset KUBECONFIG && \
	kubectl config set-context kind-ecoqube-mgmt-dev-admin@kind-ecoqube-mgmt-dev && \
	tilt up --file=management.tiltfile --port="10350"

tilt-prepare-wkld:
	export KUBECONFIG="${CURDIR}/${CAPI_WKLD_CLUSTER_NAME}.kubeconfig" && \
	kubectl config set-context ${CAPI_WKLD_CLUSTER_NAME}-admin@${CAPI_WKLD_CLUSTER_NAME} && \
	./hack/restart-containerd.sh && \
	./hack/document-local-registry.sh

tilt-workload-up: tilt-prepare-wkld
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
	docker system prune
