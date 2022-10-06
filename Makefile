MKFILE_PATH  := $(abspath $(lastword $(MAKEFILE_LIST)))
ROOT_DIR := $(dir $(MKFILE_PATH))
HACK_DIR := $(ROOT_DIR)/hack
COMMON_SCRIPT := $(HACK_DIR)/common.sh
LOCAL_ROOT := $(ROOT_DIR)/.local
export LOCAL_ROOT

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
