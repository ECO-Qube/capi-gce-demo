.EXPORT_ALL_VARIABLES:
CAPI_KIND_CLUSTER_NAME = ecoqube-dev
KIND_CLUSTER_VERSION = v1.27.1
CLUSTER_TOPOLOGY = true
EXP_CLUSTER_RESOURCE_SET = true

.PHONY: all $(MAKECMDGOALS)

all: tilt-prepare tilt-up

tilt-prepare:
	./hack/kind-install-for-capd.sh

tilt-up: tilt-prepare
	tilt up

clean:
	kind delete cluster --name=${CAPI_KIND_CLUSTER_NAME}
	docker ps --filter name="kind-registry" -aq | xargs docker stop | xargs docker rm
