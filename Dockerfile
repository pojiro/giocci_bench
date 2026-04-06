FROM hexpm/elixir:1.19.5-erlang-28.3-ubuntu-noble-20251013

ARG USER_NAME=dev
ARG USER_UID=1000
ARG USER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive \
  LANG=C.UTF-8 \
  LC_ALL=C.UTF-8

RUN apt-get update && \
  apt-get install -y --no-install-recommends \
  build-essential \
  ca-certificates \
  chrony \
  git \
  iputils-ping \
  procps && \
  rm -rf /var/lib/apt/lists/*

RUN groupadd --non-unique --gid "${USER_GID}" "${USER_NAME}" && \
  useradd --non-unique --uid "${USER_UID}" --gid "${USER_GID}" --create-home --shell /bin/bash "${USER_NAME}" && \
  mkdir -p "/home/${USER_NAME}/.mix" "/home/${USER_NAME}/.hex" && \
  chown -R "${USER_UID}:${USER_GID}" "/home/${USER_NAME}"

WORKDIR /workspace
USER ${USER_NAME}

CMD ["bash"]