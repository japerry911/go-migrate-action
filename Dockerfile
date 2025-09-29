FROM golang:1.25.1-bookworm as builder

ARG INPUT_GOMIGRATE_VERSION
ENV GOMIGRATE_VERSION=$INPUT_GOMIGRATE_VERSION

# Install golang-migrate
RUN curl -L https://github.com/golang-migrate/migrate/releases/download/${GOMIGRATE_VERSION}/migrate.linux-amd64.tar.gz | tar xvz

# Install gcloud SDK
RUN apt-get update -q && \
    apt-get install -y --no-install-recommends curl gnupg && \
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/google-cloud-sdk.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/google-cloud-sdk.gpg] https://packages.cloud.google.com/apt cloud-sdk main" > /etc/apt/sources.list.d/google-cloud-sdk.list && \
    apt-get update -q && \
    apt-get -y install google-cloud-sdk netcat-openbsd && \
    # Clean up
    apt-get autoremove -y && \
    apt-get clean -y && \
    rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
