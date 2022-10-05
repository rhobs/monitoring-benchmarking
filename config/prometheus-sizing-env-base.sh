#!/usr/bin/env bash

# From https://github.com/cloud-bulldozer/kube-burner/releases
kb_os_url_component='Linux'
if [[ "${OSTYPE:-linux}" == "darwin"* ]]
then
    kb_os_url_component='Darwin'
fi

## This downloads kubeburner to $(pwd)
export KUBE_BURNER_RELEASE_URL="https://github.com/cloud-bulldozer/kube-burner/releases/download/v0.16.2/kube-burner-0.16.2-${kb_os_url_component}-x86_64.tar.gz"
export ENABLE_INDEXING=false
export WRITE_TO_FILE=true
