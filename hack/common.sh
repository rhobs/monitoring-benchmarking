#!/usr/bin/env bash

set -eu
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
LOGS_ROOT="${SCRIPT_DIR}/../logs"
MON_BENCHMARKS_ROOT="${HOME}/.rh/monitoring-benchmarks"
CONFIG_ROOT="${SCRIPT_DIR}/../config"

mkdir -p "${LOGS_ROOT}"
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