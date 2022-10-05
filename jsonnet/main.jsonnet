local benchmarks_namespace = "monitoring-benchmarks";

local namespace() =
{
    apiVersion: "v1",
    kind: "Namespace",
    metadata: {
        name: benchmarks_namespace
    }
};

local benchmarks_pvc() = 
{
    apiVersion: "v1",
    kind: "PersistentVolumeClaim",
    metadata: {
        name: "monitoring-benchmarks-data-claim",
        namespace: benchmarks_namespace,
        annotations: {
            "volume.beta.kubernetes.io/storage-class": "gp2"
        }
            
    },
    spec: {
        accessModes: [ "ReadWriteOnce" ],
        resources: {
            requests: {
                storage: "4Gi"
            }
        }
    }
};

local benchmarks_runner_replica_set(config) =
{
    apiVersion: "apps/v1",
    kind: "ReplicaSet",
    metadata: {
      name: "benchmarks-runner",
      namespace: benchmarks_namespace,
      labels: {
        app: "monitoring-benchmarks"
      },
    },
    spec: {
        replicas: 1,
        selector: {
            matchLabels: {
                app: "monitoring-benchmarks",
            },
        },
        template: {
            metadata: {
                labels: {
                    app: "monitoring-benchmarks",
                }
            },
            spec: {
                serviceAccountName: "benchmarks-runner",
                volumes: [
                    {
                        name: "benchmarks-runner",
                        persistentVolumeClaim: {
                            claimName: "monitoring-benchmarks-data-claim"
                        },
                    }
                ],
                containers: [
                    {
                        name: "runner",
                        image: config['runner_image'],
                        imagePullPolicy: 'Always',
                        command: [ 'make'],
                        args: ['run/benchmarks/continuously' ],
                        volumeMounts: [
                            {
                                name: 'benchmarks-runner',
                                mountPath: '/var/lib/benchmarks'
                            }
                        ],
                        env: [
                            {
                                name: 'BENCHMARKS_RUNS_ROOT', 
                                value: '/var/lib/benchmarks/runs'
                            },
                            {   
                                name: 'PODS_PER_NODE',
                                value: std.toString(config['pods_per_node'])
                            },
                            {   
                                name: 'POD_CHURNING_PERIOD',
                                value: config['pod_churning_period']
                            },
                            {   
                                name: 'NUMBER_OF_NS',
                                value: std.toString(config['number_of_ns'])
                            },
                        ],
                        securityContext: {
                            allowPrivilegeEscalation: false,
                            capabilities: {
                                drop: [ "ALL" ],
                            },
                            runAsNonRoot: true,
                            seccompProfile: {
                                type: 'RuntimeDefault',
                            }
                        }
                    }
                ]
            }
        }
    }
};

local benchmarks_runner_rbac() =
[
{
    apiVersion: "rbac.authorization.k8s.io/v1",
    kind: "ClusterRole",
    metadata: {
        name: "benchmarks-runner-role"
    },
    rules: [
        {
            apiGroups: ['*'], resources: ['*'], verbs: ['*'],
        }
    ]
},
{
    apiVersion: "v1",
    kind: "ServiceAccount",
    metadata: {
      name: "benchmarks-runner",
      namespace: benchmarks_namespace
    }
},{
    apiVersion: "rbac.authorization.k8s.io/v1",
    kind: "ClusterRoleBinding",
    metadata: {
        name: "benchmarks-runner-rolebinding",
    },
    roleRef: {
      apiGroup: "rbac.authorization.k8s.io",
      kind: "ClusterRole",
      name: "benchmarks-runner-role"
    },
    subjects: [
        {
            kind: "ServiceAccount",
            name: "benchmarks-runner",
            namespace: benchmarks_namespace
        }
    ]
}
];

function(config)
    [ namespace(),  benchmarks_pvc() ] +
    benchmarks_runner_rbac() + [ benchmarks_runner_replica_set(config) ]
