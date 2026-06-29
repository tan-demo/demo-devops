FROM alpine:3.22

ARG KUBECTL_VERSION=v1.36.2
ARG HELM_VERSION=v4.2.2
ARG TERRAFORM_VERSION=1.15.7
ARG K6_VERSION=v2.0.0
ARG K3D_VERSION=v5.9.0
ARG ARGOCD_VERSION=v3.4.4

RUN apk add --no-cache \
        bash curl git jq yq openssl ca-certificates unzip tar \
        docker-cli coreutils gettext

RUN set -eux; \
    case "$(uname -m)" in \
      x86_64) TARGETARCH=amd64 ;; \
      aarch64|arm64) TARGETARCH=arm64 ;; \
      *) echo "unsupported build arch: $(uname -m)" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /usr/local/bin/kubectl \
        "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl"; \
    chmod +x /usr/local/bin/kubectl; \
    curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz" \
        | tar -xz -C /tmp; \
    mv "/tmp/linux-${TARGETARCH}/helm" /usr/local/bin/helm; \
    curl -fsSL -o /tmp/tf.zip \
        "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip"; \
    unzip -o /tmp/tf.zip -d /usr/local/bin; \
    curl -fsSL "https://github.com/grafana/k6/releases/download/${K6_VERSION}/k6-${K6_VERSION}-linux-${TARGETARCH}.tar.gz" \
        | tar -xz -C /tmp; \
    mv "/tmp/k6-${K6_VERSION}-linux-${TARGETARCH}/k6" /usr/local/bin/k6; \
    curl -fsSL -o /usr/local/bin/k3d \
        "https://github.com/k3d-io/k3d/releases/download/${K3D_VERSION}/k3d-linux-${TARGETARCH}"; \
    chmod +x /usr/local/bin/k3d; \
    curl -fsSL -o /usr/local/bin/argocd \
        "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-${TARGETARCH}"; \
    chmod +x /usr/local/bin/argocd; \
    rm -rf /tmp/*

ENV TOOLBOX=1
ENV KUBECONFIG=/kubeconfig/config
WORKDIR /workspace

RUN kubectl version --client=true 2>/dev/null | head -1 || true; \
    helm version --short || true; \
    terraform version | head -1 || true; \
    k6 version || true; \
    k3d version || true

ENTRYPOINT ["/workspace/toolbox/entrypoint.sh"]
