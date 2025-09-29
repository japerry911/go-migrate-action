#!/usr/bin/env bash

# A wrapper function to handle the entire tunnel lifecycle for a given command.
function _run_with_tunnel() {
    # Configuration for the GCP bastion
    local LOCAL_PORT="5432"
    local REMOTE_PORT="5432"

    # The command to execute once the tunnel is established.
    if [[ "$#" -eq 0 ]]; then
        echo "❌ _run_with_tunnel requires a command to execute."
        return 1
    fi

    # Your GCP username (can be overridden with the SSH_NAME environment variable)
    local SSH_NAME="${INPUT_SSH_NAME}"
    if [[ -z $SSH_NAME ]]; then
        echo "❌ SSH_NAME is not set. Please set the SSH_NAME environment variable."
        exit 1
    fi

    local BASTION_VM_NAME="${INPUT_BASTION_VM_NAME}"
    if [[ -z $BASTION_NAME ]]; then
        echo "❌ BASTION_VM_NAME is not set. Please set the BASTION_VM_NAME environment variable."
        exit 1
    fi
grep -rni --color=always 'password\|secret\|token\|key\|private' .grep -rni --color=always 'password\|secret\|token\|key\|private' .grep -rni --color=always 'password\|secret\|token\|key\|private' .
    local BASTION_VM_ZONE="${INPUT_BASTION_VM_ZONE}"
    if [[ -z $BASTION_VM_ZONE ]]; then
        echo "❌ BASTION_VM_ZONE is not set. Please set the BASTION_VM_ZONE environment variable."
        exit 1
    fi

    echo "➡️  Step 1 of 5: Checking bastion host status..."
    local bastion_status
    bastion_status=$(gcloud compute instances describe "${BASTION_VM_NAME}" --zone="${BASTION_VM_ZONE}" --project="${GCP_PROJECT_ID}" --format="value(status)" 2>/dev/null || echo "NOT_FOUND")

    if [ "${bastion_status}" != "RUNNING" ]; then
        echo "ℹ️  Bastion host is not running (status: ${bastion_status}). Starting it now..."
        gcloud compute instances start "${BASTION_VM_NAME}" --zone="${BASTION_VM_ZONE}" --project="${GCP_PROJECT_ID}" --quiet
        echo "⏳ Waiting for bastion host to be ready (this may take a few minutes)..."
        gcloud compute instances wait-for-service-port "${BASTION_VM_NAME}" --zone="${BASTION_VM_ZONE}" --project="${GCP_PROJECT_ID}" --port 22 --timeout 300
        echo "✅ Bastion host is RUNNING."
    else
        echo "✅ Bastion host is already running."
    fi

    echo "➡️  Step 2 of 5: Checking for existing tunnel..."
    if command -v lsof >/dev/null 2>&1 && lsof -ti:"${LOCAL_PORT}" >/dev/null; then
        echo "ℹ️  An existing process was found on port ${LOCAL_PORT}. Terminating it..."
        lsof -ti:"${LOCAL_PORT}" | xargs kill -9
        sleep 1 # Brief pause to allow the port to be released
    else
        echo "✅ Port ${LOCAL_PORT} is clear."
    fi

    echo "➡️  Step 3 of 5: Starting SSH tunnel in the background..."
    # Bind to 0.0.0.0 so the tunnel is accessible from outside the dev container
    gcloud compute ssh "${SSH_NAME}@${BASTION_VM_NAME}" --zone="${BASTION_VM_ZONE}" --project="${GCP_PROJECT_ID}" -- -N -L "0.0.0.0:${LOCAL_PORT}:localhost:${REMOTE_PORT}" &
    local TUNNEL_PID=$!

    # Cleanup function to kill the tunnel when the script exits
    cleanup() {
        echo "ℹ️  Shutting down SSH tunnel (PID: ${TUNNEL_PID})..."
        if [ -n "${TUNNEL_PID}" ]; then
            # Suppress "No such process" error if the process is already gone
            kill "${TUNNEL_PID}" 2>/dev/null || true
        fi
    }
    trap cleanup EXIT

    echo "➡️  Step 4 of 5: Waiting for tunnel to be established..."
    while ! nc -z localhost "${LOCAL_PORT}"; do
        sleep 0.5 # wait for half a second before checking again
    done
    echo "✅ Tunnel is ready."

    echo "➡️  Step 5 of 5: Executing command..."
    "$@"
    local exit_code=$?

    # Manually trigger cleanup before exiting
    cleanup
    trap - EXIT # Clear the trap
    
    return $exit_code
}

# URL-encodes a string to be safely used in a URL.
function _urlencode() {
    local string="${1}"
    local strlen=${#string}
    local encoded=""
    local pos c o

    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9] ) o="${c}" ;;
            * )               printf -v o '%%%02x' "'$c"
        esac
        encoded+="${o}"
    done

    echo "${encoded}"
}

# Connects to the private database and runs migrations.
function postgres:migrate() {
    local encoded_password
    encoded_password=$(_urlencode "${INPUT_DB_PASSWORD}")
    local MIGRATE_CMD_ARRAY=(migrate -database "postgres://${INPUT_DB_USER}:${encoded_password}@127.0.0.1:5432/${INPUT_DB_NAME}?sslmode=disable" -path migrations)
    echo "🚀 Running database migrations..."
    _run_with_tunnel "${MIGRATE_CMD_ARRAY[@]}" "up"
    echo "✅ Migrations applied successfully."
}

echo "Starting golang-migrate CLI command..."

# Download golang-migrate at runtime using the version from INPUT_GOMIGRATE_VERSION
if [[ -z "$INPUT_GOMIGRATE_VERSION" ]]; then
    echo "❌ INPUT_GOMIGRATE_VERSION is not set."
    exit 1
fi

echo "⬇️  Downloading golang-migrate version $INPUT_GOMIGRATE_VERSION..."
curl -sSL -o migrate.tar.gz "https://github.com/golang-migrate/migrate/releases/download/${INPUT_GOMIGRATE_VERSION}/migrate.linux-amd64.tar.gz"
if ! tar -xzf migrate.tar.gz; then
    echo "❌ Failed to extract golang-migrate. Check if the version is correct: $INPUT_GOMIGRATE_VERSION"
    exit 1
fi
chmod +x migrate && mv migrate /usr/local/bin/migrate
rm -f migrate.tar.gz

postgres:migrate
