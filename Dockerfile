# Find eligible builder and runner images on Docker Hub. We use Ubuntu/Debian instead of
# Alpine to avoid DNS resolution issues in production.
#
# https://hub.docker.com/r/hexpm/elixir/tags?page=1&name=ubuntu
# https://hub.docker.com/_/ubuntu?tab=tags
#
#
# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the build image
#   - https://hub.docker.com/_/debian?tab=tags&page=1&name=bullseye-20210902-slim - for the release image
#   - https://pkgs.org/ - resource for finding needed packages
#
ARG REPOSITORY="https://github.com/zachallaun/flytail"

ARG BUILDER_IMAGE="hexpm/elixir:1.13.4-erlang-24.3.3-ubuntu-focal-20211006"
ARG RUNNER_IMAGE="ubuntu:focal-20211006"

FROM ${BUILDER_IMAGE} as builder

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

# install build dependencies
RUN set -eux; \
  \
  apt-get update -y; \
  apt-get install -y \
  curl \
  ca-certificates \
  ; \
  \
  curl -fsSL https://deb.nodesource.com/setup_14.x | bash -; \
  \
  apt-get update -y; \
  apt-get install -y \
  build-essential \
  git \
  nodejs \
  python3 \
  ; \
  \
  curl -sL https://dl.yarnpkg.com/debian/pubkey.gpg | gpg --dearmor | tee /usr/share/keyrings/yarnkey.gpg >/dev/null; \
  echo "deb [signed-by=/usr/share/keyrings/yarnkey.gpg] https://dl.yarnpkg.com/debian stable main" | tee /etc/apt/sources.list.d/yarn.list; \
  apt-get update -y; \
  apt-get install -y \
  yarn \
  ; \
  apt-get clean; \
  rm -f /var/lib/apt/lists/*_*

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
  mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv

COPY lib lib
COPY assets assets

# compile assets
RUN mix assets.deploy

# Compile the release
RUN mix compile

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE}

ARG TAILSCALE_VERSION=1.26.1
ARG OVERMIND_VERSION=2.2.2

ENV TAILSCALE_VERSION=${TAILSCALE_VERSION}
RUN set -eux; \
  \
  apt-get update -y; \
  apt-get install -y \
  curl \
  ca-certificates \
  ; \
  curl -fsSL https://pkgs.tailscale.com/stable/debian/bullseye.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null; \
  curl -fsSL https://pkgs.tailscale.com/stable/debian/bullseye.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list; \
  \
  apt-get update -y; \
  apt-get install -y \
  libstdc++6 \
  openssl \
  libncurses5 \
  locales \
  nftables \
  tailscale=${TAILSCALE_VERSION} \
  tmux \
  gosu \
  ; \
  apt-get clean; \
  rm -f /var/lib/apt/lists/*_*; \
  gosu nobody true

ENV OVERMIND_VERSION=${OVERMIND_VERSION}
RUN set -eux; \
  \
  mkdir -p /tmp/build; \
  cd /tmp/build; \
  curl -fsSL https://github.com/DarthSim/overmind/releases/download/v${OVERMIND_VERSION}/overmind-v${OVERMIND_VERSION}-linux-amd64.gz | gunzip > overmind; \
  mv overmind /usr/bin/overmind; \
  chmod +x /usr/bin/overmind; \
  cd; \
  rm -rf /tmp/build

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR /app

COPY docker/Procfile.fly Procfile
COPY docker/tailscale-up.sh docker/wait-for-tailscale.sh docker/
RUN chown -R nobody /app

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/prod/rel/flytail ./

COPY docker/fly-entrypoint.sh /docker-entrypoint.sh

ENV OVERMIND_NO_PORT=1
ENV OVERMIND_CAN_DIE=tailscaleup
ENV OVERMIND_STOP_SIGNALS="app=TERM"

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["overmind", "start"]

# Appended by flyctl
ENV ECTO_IPV6 true
ENV ERL_AFLAGS "-proto_dist inet6_tcp"

ARG vcs_ref
LABEL org.label-schema.vcs-ref=$vcs_ref \
  org.label-schema.vcs-url="${REPOSITORY}" \
  SERVICE_TAGS=$vcs_ref
ENV VCS_REF ${vcs_ref}
ENV APP_REVISION ${vcs_ref}
