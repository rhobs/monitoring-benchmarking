# monitoring-benchmarking

Performance tests for monitoring stack

## Prerequisites

Fulfill the following prerequisites before using the scripts.

### Get IAM user in our dev account, and setup AWS CLI profile

FIXME: Acccount name TBC

Install the AWS CLI following [its documentation](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html).  
Creare an AWS CLI profile called `openshift-monitoring-benchmarks` by running `aws configure --profile=openshift-monitoring-benchmarks` and introducing the credentials you obtained when setting up your IAM user. If all went well you should be able to run the following command successfully.  

```bash
export AWS_PROFILE=openshift-monitoring-benchmarks
aws iam get-user 
```

### Install the openshift installer

Download the OpenShift installer CLI and your pull secret from [here](https://console.redhat.com/openshift/install/aws/installer-provisioned). Add OpenShift installer CLI to your `PATH`, in MacOSX you can do that by adding `export PATH=${PATH}:PATH_TO_openshift-install` to `~/.bash_profile`. Verify by checking the following command runs succesfully.

```bash
openshift-install --help
```

## Create and delete cluster

Create a cluster as follows:

```bash
export AWS_PROFILE=openshift-monitoring-benchmarks
# Define env vars to locate your pull secret, and a public ssh key file to access the cluster nodes.
## path to file where you stored your pull secret
export PULL_SECRET_PATH=...
## path to ssh public key to use to setup ssh access to cluster nodes
export SSH_KEY_PATH=...

# Cluster must include your RH SSO login, this target ensures that
export cluster_name=$(make cluster/new-name)
# adjust accordingly
export num_workers=3
# see available releases at https://quay.io/repository/openshift-release-dev/ocp-release?tab=tags, suffix '-x86_64'
# is automatically added
export ocp_release='4.11.7'
# Check stdout for cluster login (will be removed from log)
make cluster/create
# get cluster credentials
export KUBECONFIG=$(make cluster/kubeconfig)
```

Delete a cluster as follows:

```bash
# If needed see latest cluster name as follows
make cluster/list
# cluster to delete
export cluster_name=...
make cluster/delete
```