MKFILE_PATH  := $(abspath $(lastword $(MAKEFILE_LIST)))
ROOT_DIR := $(dir $(MKFILE_PATH))
HACK_DIR := $(ROOT_DIR)/hack
COMMON_SCRIPT := $(HACK_DIR)/common.sh
LOCAL_ROOT := $(ROOT_DIR)/.local
export LOCAL_ROOT

MANIFESTS_ROOT := $(LOCAL_ROOT)/manifests
export MANIFESTS_ROOT
E2E_BENCHMARKING_ROOT := $(LOCAL_ROOT)/e2e-benchmarking
export E2E_BENCHMARKING_ROOT
E2E_BENCHMARKING_HASH := 'ec219202f02e766214b9c66618b41c717a58189a'

BIN_DIR := $(LOCAL_ROOT)/bin
JSONNET_BIN=$(BIN_DIR)/jsonnet
TOOLING=$(JSONNET_BIN)

IMAGE_GROUP := openshift
IMAGE_NAME := monitoring-benchmarking
IMAGE_VERSION := 0.1.0
IMAGE_TAG := $(IMAGE_GROUP)/$(IMAGE_NAME):$(IMAGE_VERSION)
EXTERNAL_IMAGE_TAG := quay.io/${USER}/$(IMAGE_NAME):$(IMAGE_VERSION)

##############################
## Clusters
##############################
.PHONY: cluster/new-name
cluster/new-name:
	@source $(COMMON_SCRIPT) && echo "$${USER}-prombenchmark-$$(date_w_format)"

.PHONY: cluster/create
cluster/create:
	source $(COMMON_SCRIPT) && create_cluster "${cluster_name}" "${num_workers}" "${ocp_release}"

.PHONY: cluster/delete
cluster/delete:
	source $(COMMON_SCRIPT) && delete_cluster "${cluster_name}"

.PHONY: cluster/kubeconfig
cluster/kubeconfig:
	@source $(COMMON_SCRIPT) && echo "$$(cluster_config_dir "${cluster_name}")/auth/kubeconfig"

.PHONY: cluster/list
cluster/list:
	source $(COMMON_SCRIPT) && ls -ltr "$${MON_BENCHMARKS_ROOT}/clusters"


##############################
## Images
##############################
PHONY: image/build/local
image/build/local:
	docker build -t $(IMAGE_TAG) .

.PHONY: image/shell/local
image/shell/local:
	docker run -it --rm --entrypoint /bin/bash $(IMAGE_TAG)

.PHONY: image/push
image/push: image/build/local
	echo 'Assumming logged with `docker login -u "${USER}" quay.io`'
	docker tag $(IMAGE_TAG) quay.io/${USER}/$(IMAGE_NAME):$(IMAGE_VERSION)
	docker push $(EXTERNAL_IMAGE_TAG)
	echo "Asumming project is public at https://quay.io/repository/${USER}/$(IMAGE_NAME)?tab=settings "


##############################
## Benchmarks run
##############################
$(LOCAL_ROOT):
	mkdir -p $(LOCAL_ROOT)

$(E2E_BENCHMARKING_ROOT): $(LOCAL_ROOT)
	ls $(E2E_BENCHMARKING_ROOT) || ( cd $(LOCAL_ROOT) && git clone https://github.com/cloud-bulldozer/e2e-benchmarking.git && cd e2e-benchmarking && git checkout $(E2E_BENCHMARKING_HASH) )

.PHONY: cloud-bulldozer/e2e-benchmarking
cloud-bulldozer/e2e-benchmarking: $(E2E_BENCHMARKING_ROOT)

# Example: make run/benchmarks run_root=".local/run_benchmarks/$(date +%Y-%m-%d--%H-%M-%S)" pods_per_node=10 pod_churning_period='1m' number_of_ns=2
.PHONY: run/benchmarks
run/benchmarks: $(E2E_BENCHMARKING_ROOT)
	source $(COMMON_SCRIPT) && run_benchmarks "${run_root}" "${pods_per_node}" "${pod_churning_period}" "${number_of_ns}"

.PHONY: run/benchmarks/continuously
run/benchmarks/continuously: $(E2E_BENCHMARKING_ROOT)
	source $(COMMON_SCRIPT) && run_benchmarks_continuously


##############################
## Deployment
##############################
$(BIN_DIR):
	mkdir -p $(BIN_DIR)

$(TOOLING): $(BIN_DIR)
	@echo Installing tools
	@cd $(ROOT_DIR)/hack/tools && go list -mod=mod -tags tools -f '{{ range .Imports }}{{ printf "%s\n" .}}{{end}}' ./ | xargs -tI % go build -mod=mod -o $(BIN_DIR) %

.PHONY: jsonnet/build
jsonnet/build: $(TOOLING)
	source $(COMMON_SCRIPT) && jsonnet_build "{runner_image: \"$(EXTERNAL_IMAGE_TAG)\"} + $$(cat ${benchmark_config})"

.PHONY: benchmarks/deploy
benchmarks/deploy: jsonnet/build
	jq -r .[] $(MANIFESTS_ROOT)/main.json | oc apply -f -

.PHONY: benchmarks/undeploy
benchmarks/undeploy: jsonnet/build
	jq -r .[] $(MANIFESTS_ROOT)/main.json | oc delete --ignore-not-found=true -f -


##############################
## Results processing
##############################
# Example: make benchmarks/data/download output=$(pwd)/.local
.PHONY: benchmarks/download
benchmarks/data/download: 
	oc -n monitoring-benchmarks rsync $$(oc -n monitoring-benchmarks get pod -l app=monitoring-benchmarks -o=jsonpath='{.items[].metadata.name}'):/var/lib/benchmarks/runs "${output}/" -c runner
	echo
	echo "See benchmark data at ${output}/runs, only directories with a SUCCESS file contain a completed benchmark run"
