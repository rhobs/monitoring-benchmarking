#!/usr/bin/env bash

set -eu
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
LOGS_ROOT="${SCRIPT_DIR}/../logs"
MON_BENCHMARKS_ROOT="${HOME}/.rh/monitoring-benchmarks"
CONFIG_ROOT="${SCRIPT_DIR}/../config"
JSONNET_ROOT="${SCRIPT_DIR}/../jsonnet"

mkdir -p "${LOGS_ROOT}" "${MANIFESTS_ROOT}"
export PATH="${LOCAL_ROOT}/bin:${PATH}"

function date_w_format {
  date +%Y-%m-%d--%H-%M-%S
}

function log {
    log_file="${1}"
    msg="${2}"

    touch "${log_file}"
    echo "[$(date_w_format)] ${msg}" | tee -a "${log_file}"
}

function cluster_config_dir {
    cluster_name="${1}"

    conf_dir="${MON_BENCHMARKS_ROOT}/clusters/${cluster_name}"
    mkdir -p "${conf_dir}"
    echo "${conf_dir}"
}

function create_cluster {
    CLUSTER_NAME="${1}"
    NUM_WORKERS="${2}"
    OCP_RELEASE="${3}"

    log_file="${LOGS_ROOT}/create_cluster-$(date_w_format).log"
    echo "Using log file ${log_file}"
    OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="quay.io/openshift-release-dev/ocp-release:${OCP_RELEASE}-x86_64"
    log "${log_file}" "Using OCP image ${OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE}"
    config_dir="$(cluster_config_dir "${CLUSTER_NAME}")"
    log "${log_file}" "Using cluster config dir ${config_dir}"
    
    SSH_KEY=$(cat "${SSH_KEY_PATH}")
    PULL_SECRET=$(cat "${PULL_SECRET_PATH}")
    install_config_file="${config_dir}/install-config.yaml"
    < "${CONFIG_ROOT}/install-config.template.yaml" \
      NUM_WORKERS="${NUM_WORKERS}" SSH_KEY="${SSH_KEY}" PULL_SECRET="${PULL_SECRET}" CLUSTER_NAME="${CLUSTER_NAME}"\
      envsubst > "${install_config_file}"
    install_config_redacted=$(grep -v pullSecret "${install_config_file}" | grep -v ssh)
    log "${log_file}" "Using install configuration ${install_config_redacted}"

    OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="${OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE}" openshift-install --dir="${config_dir}" create cluster 2>&1 | tee -a "${log_file}"
    < "${log_file}" grep -v password > "${log_file}.clean"
    mv "${log_file}.clean" "${log_file}"

    log "${log_file}" "Cluster kubeconfig available at ${config_dir}/auth/kubeconfig"

    unset SSH_KEY
    unset PULL_SECRET
    unset CLUSTER_NAME
    unset NUM_WORKERS

    echo
    echo "See logs at ${log_file}"
}

function delete_cluster {
    CLUSTER_NAME="${1}"
    
    log_file="${LOGS_ROOT}/delete_cluster-$(date_w_format).log"
    echo "Using log file ${log_file}"
    config_dir="$(cluster_config_dir "${CLUSTER_NAME}")"

    openshift-install destroy cluster --dir="${config_dir}" --log-level=debug 2>&1 | tee -a "${log_file}"
}

function jsonnet_build {
    CONFIG="${1}"

    rm -rf "${MANIFESTS_ROOT}"
    mkdir -p "${MANIFESTS_ROOT}"
    jsonnet "${JSONNET_ROOT}/main.jsonnet" > "${MANIFESTS_ROOT}/main.json" --tla-code config="${CONFIG}"
}

function run_benchmarks {
    run_root="${1}"
    PODS_PER_NODE="${2}"
    POD_CHURNING_PERIOD="${3}"
    NUMBER_OF_NS="${4}"

    mkdir -p "${run_root}"

    echo "Aborting previous uncompleted runs"
    benchmarks_ns=$(kubectl get namespaces | grep -i prometheus-sizing | awk '{ print $1 }')
    if [ -n "${benchmarks_ns}" ]
    then
        benchmarks_ns_arr=(${benchmarks_ns})
        for ns in "${benchmarks_ns_arr[@]}"
        do
            kubectl delete namespace "${ns}"
        done
    fi
    export PODS_PER_NODE=${PODS_PER_NODE}
    export POD_CHURNING_PERIOD=${POD_CHURNING_PERIOD}
    export NUMBER_OF_NS=${NUMBER_OF_NS}
    METRICS="${CONFIG_ROOT}/prometheus-sizing-metrics.yaml"
    export METRICS
    source "${CONFIG_ROOT}/prometheus-sizing-env-base.sh"
    env > "${run_root}/env.sh"

    workload_root="${E2E_BENCHMARKING_ROOT}/workloads/prometheus-sizing"
    rm -rf "${workload_root}/collected-metrics/*"
    # so the downloaded `kube-burner` command is available for the workload script
    export PATH="${workload_root}":"${PATH}"
    pushd "${workload_root}"
    ./prometheus-sizing-churning.sh
    popd
    mv "${workload_root}/collected-metrics" "${run_root}/metrics"

    # Confirm the run fully completed successfully
    touch "${run_root}/SUCCESS"
    echo "Benchmark run completed successfully, see metrics at ${run_root}/metrics"
}

function run_benchmarks_continuously {
    # Assuming env vars defined: BENCHMARKS_RUNS_ROOT PODS_PER_NODE POD_CHURNING_PERIOD NUMBER_OF_NS

    # Make function `openshift_login` a no-op so we can use RBAC credentials for auth
    sed -i '/function\sopenshift_login.*/a return 0' "${E2E_BENCHMARKING_ROOT}/utils/common.sh"
    # Use `kubectl` as `oc`
    function oc { kubectl "$@"; }
    export -f oc

    while true
    do
        run_root="${BENCHMARKS_RUNS_ROOT}/$(date_w_format)"
        mkdir -p "${run_root}"
        echo
        echo
        echo "Starting new benchmark run at ${run_root}"
        run_benchmarks "${run_root}" "${PODS_PER_NODE}" "${POD_CHURNING_PERIOD}" "${NUMBER_OF_NS}"
        echo "Completed benchmark run at ${run_root}"
    done
}
