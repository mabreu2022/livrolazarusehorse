# ===================================================================
# STAGE 1: Compilador e Construtor (Builder)
# ===================================================================
FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    fpc \
    fpc-source \
    build-essential \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY . .

RUN mkdir -p /app/bin && \
    fpc -B \
        -Mobjfpc \
        -Sh \
        -O3 \
        -XX \
        -Xs \
        -CX \
        -Fi/app/src \
        -Fu/app/src/** \
        -FE/app/bin \
        -o/app/bin/connect_os_api \
        /app/src/ConnectOSApi.lpr

# ===================================================================
# STAGE 2: Imagem de Producao Minimalista (Runner)
# ===================================================================
FROM ubuntu:24.04 AS runner

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libssl3 \
    libfbclient2 \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -r -s /usr/sbin/nologin -d /app connectos

WORKDIR /app

RUN mkdir -p /app/storage /app/logs && \
    chown -R connectos:connectos /app

COPY --from=builder /app/bin/connect_os_api /app/connect_os_api
RUN chmod +x /app/connect_os_api && \
    chown connectos:connectos /app/connect_os_api

USER connectos

EXPOSE 9000

HEALTHCHECK --interval=15s --timeout=3s --retries=3 \
    CMD curl -f http://localhost:9000/ping || exit 1

ENTRYPOINT ["/app/connect_os_api"]
