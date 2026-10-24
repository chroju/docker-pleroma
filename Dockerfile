FROM elixir:1.20.4-alpine

ARG PLEROMA_VER=develop
ARG UID=911
ARG GID=911
ENV MIX_ENV=prod
ENV ERL_AFLAGS="+JMsingle true"
# latest-stable の CMake 4 は cmake_minimum_required が 3.5 未満の CMakeLists.txt を拒否する。
# 依存の fast_html（lexbor）が該当するため、互換モードで設定を通す
ENV CMAKE_POLICY_VERSION_MINIMUM=3.5

RUN echo "http://nl.alpinelinux.org/alpine/latest-stable/main" >> /etc/apk/repositories \
    && apk update \
    && apk add git gcc g++ musl-dev make cmake file-dev \
    exiftool imagemagick libmagic ncurses postgresql-client ffmpeg \
    ca-certificates openssl \
    && apk upgrade --no-cache ca-certificates

# eMudhra の中間 CA 漏えい（2026-10）で失効した emSign ECC Root CA - G3 が
# システムの CA ストアに残っていれば、古い ca-certificates なのでビルドを止める
RUN if openssl crl2pkcs7 -nocrl -certfile /etc/ssl/certs/ca-certificates.crt \
        | openssl pkcs7 -print_certs -noout | grep -q 'CN = emSign ECC Root CA - G3'; then \
        echo "ca-certificates still trusts emSign ECC Root CA - G3" >&2; exit 1; \
    fi

RUN addgroup -g ${GID} pleroma \
    && adduser -h /pleroma -s /bin/false -D -G pleroma -u ${UID} pleroma

ARG DATA=/var/lib/pleroma
RUN mkdir -p /etc/pleroma \
    && chown -R pleroma /etc/pleroma \
    && mkdir -p ${DATA}/uploads \
    && mkdir -p ${DATA}/static \
    && chown -R pleroma ${DATA}

USER pleroma
WORKDIR /pleroma

RUN git init \
    && git remote add origin https://git.pleroma.social/pleroma/pleroma.git \
    && git fetch --depth 1 origin tag ${PLEROMA_VER} \
    && git checkout tags/${PLEROMA_VER}

# certifi と castore が同梱する CA バンドルは更新が遅れるため、システムの CA ストアで上書きする
# （certifi は cacerts.pem をコンパイル時に取り込むので、mix release より前に置き換える）
RUN echo "import Mix.Config" > config/prod.secret.exs \
    && mix local.hex --force \
    && mix local.rebar --force \
    && mix deps.get --only prod \
    && cp /etc/ssl/certs/ca-certificates.crt deps/certifi/priv/cacerts.pem \
    && cp /etc/ssl/certs/ca-certificates.crt deps/castore/priv/cacerts.pem \
    && mkdir release \
    && mix release --path /pleroma

COPY --chown=pleroma --chmod=440 ./config.exs /etc/pleroma/config.exs

EXPOSE 4000

ENTRYPOINT ["/pleroma/docker-entrypoint.sh"]
