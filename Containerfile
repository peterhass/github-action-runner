FROM docker.io/library/ubuntu:24.04

ARG RUNNER_VERSION=2.337.0
ARG RUNNER_SHA256=70920811a4f8ad4328818682bca5c6469c1c942fab52448868071d0063816613
ARG HOOKS_VERSION=0.8.1
ARG HOOKS_SHA256=b38d2be4e9695eb6f143ec3b4dd4a4b800999adf9790c570dcd07dc50d9c4017

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends \
        ca-certificates curl git libicu74 libssl3 nodejs podman unzip zlib1g \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/actions-runner /opt/runner-hooks \
    && curl --fail --location --silent --show-error \
        --output /tmp/runner.tar.gz \
        "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" \
    && printf '%s  %s\n' "${RUNNER_SHA256}" /tmp/runner.tar.gz | sha256sum --check --strict \
    && tar --extract --gzip --file=/tmp/runner.tar.gz --directory=/opt/actions-runner \
    && curl --fail --location --silent --show-error \
        --output /tmp/hooks.zip \
        "https://github.com/actions/runner-container-hooks/releases/download/v${HOOKS_VERSION}/actions-runner-hooks-docker-${HOOKS_VERSION}.zip" \
    && printf '%s  %s\n' "${HOOKS_SHA256}" /tmp/hooks.zip | sha256sum --check --strict \
    && unzip -q /tmp/hooks.zip -d /opt/runner-hooks \
    && rm /tmp/runner.tar.gz /tmp/hooks.zip \
    && ln -s /usr/local/bin/github-actions-runner /usr/local/bin/docker

COPY --chmod=0755 github-actions-runner /usr/local/bin/github-actions-runner

ENV RUNNER_ALLOW_RUNASROOT=1
ENTRYPOINT ["/usr/local/bin/github-actions-runner"]
CMD ["container-run"]
