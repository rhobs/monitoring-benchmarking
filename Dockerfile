FROM registry.access.redhat.com/ubi9:9.0.0

RUN dnf -y install make git rsync && dnf -y clean all
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && \
    mv kubectl /usr/bin/kubectl
WORKDIR /usr/lib/benchmarks
RUN chmod 777 /usr/lib/benchmarks

COPY Makefile ./
COPY hack ./hack
COPY config ./config
