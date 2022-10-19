# monitoring-benchmarking high level design

This repository automates the execution of a set of performance benchmarks for the __OCP monitoring stack__. This is a small wrapper on top of [e2e-benchmarking](https://github.com/cloud-bulldozer/e2e-benchmarking) (that itself it's based on [kube-burner](https://github.com/cloud-bulldozer/kube-burner)), with specific configuration and utilities to launch OCP clusters and continuously run the benchmarks on them for a number of hours.

The whole benchmark or their subtasks are available as Makefile targets, see the [README](../README.md) for usage. 

This repository is also used to permanently store the benchmarks results, and their execution logs.

## Repository structure

The repository is structured in the following directories:

- `config` contains configuration files for the different subtasks.
- `hack` bash scripts and tools.
- `jsonnet` jsonnet files for k8s manifests to deploy the benchmarks to OpenShift.
- `logs` to permanently store the logs for benchmark executions.
- `docs` design documentation.

and the following files:

- `Makefile` contains the `make` targets that are used as entry points for the benchmarks and their subtasks.
- `Dockerfile` defines the image for the benchmark runner container that runs the benchmarks on OpenShift.

## Subtasks

### Create and delete a cluster

The `make` targets `cluster/create` and `cluster/delete` create OpenShift clusters using the  [OpenShift installer CLI](https://console.redhat.com/openshift/install/aws/installer-provisioned) `openshift-install`.  
The file `config/install-config.template.yaml` is a template for a configuration file for `openshift-install`. These targets instantiate that file according to the configurable parameters listed in the [README](../README.md), and copy them into a new subdirectory of `MON_BENCHMARKS_ROOT` ---defined in the scripts--- for the cluster, that is required by `openshift-install` for both creating and deleting a cluster.

### Continuously run a benchmark in a single cluster

The `make` targets `benchmarks/deploy`, `benchmarks/undeploy`, and `benchmarks/data/download` can be used to start running the benchmarks on a cluster, stop running the benchmarks on a cluster, and to download the benchmark results, respectively. Those targets work as follows:

- A prerequisite is running the target `make image/push` that builds an OCI image for `Dockerfile` that contains relevant scripts from this repository. The image uses `/usr/lib/benchmarks` as the working directory, and by __convention__ the results of the benchmark runs will be stored in `/var/lib/benchmarks/runs`. The image is pushed to `EXTERNAL_IMAGE_TAG` ---defined in [`Makefile`](../Makefile)--- that is a __Quay repository__ for the user running these scripts (as provided by `$USER`), that should be made public by the user as instructed in the output of this target.

- The target `benchmarks/deploy` installs the benchmarks in the cluster by rendering the jsonnet files in `jsonnet` for a __benchmark configuration file__ with the benchmark parameters described in [README](../README.md). That deploys the benchmark as a [reliable singleton](https://www.oreilly.com/library/view/kubernetes-up-and/9781491935668/) which means it runs the image above in a replica set with a single instance ---so it gets restarted by k8s---, and with a AWS EBS backed persistent volume mounted on `/var/lib/benchmarks`. 
  - The __benchmark runner__ container runs the target `run/benchmarks/continuously` that continuously runs the `prometheus-sizing` workload from [e2e-benchmarking](https://github.com/cloud-bulldozer/e2e-benchmarking) using `config/prometheus-sizing-env-base.sh` as a basic configuration that is extended with the parameters specified in the benchmark configuration file. 
  - We call __benchmark run__ to each execution of the `prometheus-sizing` workload. For each benchmark run `run/benchmarks/continuously` creates a __benchmark run results directory__ as a child of `/var/lib/benchmarks/runs` that includes a scrape of the prometheus metrics defined in `config/prometheus-sizing-metrics.yaml`. 
  - If the benchmark runner is interrupted or rescheduled then `run/benchmarks/continuously` recovers by 1) cleaning up by deleting all the namespaces for previous runs; 2) result directories from previous runs are kept by the persistent volume; 3) after a successful run the script creates an empty __`SUCCESS` file__ in the benchmark run results directory to commit it as completed with success. By __convention__, other targets should ignore directories that are missing the `SUCCESS` file, as those contain incomplete benchmark results. 

- The target `benchmarks/data/download` downloads all benchmark run results from `/usr/lib/benchmarks` of the benchmark runner container, that has the persistent volume mounted on that path.

- The target `benchmarks/undeploy` simply deletes all k8s resources created by `benchmarks/deploy`. In particular this deletes the persistent volume claim for the benchmark runner, so the benchmark results will be lost unless `benchmarks/data/download` was run before.
