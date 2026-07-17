cat > deployment/deploy.sh <<'EOF'
#!/usr/bin/env bash

# ==========================================
# RIDEWISE FASTAPI AWS EC2 DEPLOYMENT SCRIPT
# ==========================================

set -Eeuo pipefail

# ------------------------------------------
# Application settings
# ------------------------------------------

APP_NAME="ridewise-churn-api"
IMAGE_NAME="ridewise-churn-api"
IMAGE_TAG="latest"
CONTAINER_NAME="ridewise-churn-api"

HOST_PORT="8000"
CONTAINER_PORT="8000"

HEALTH_URL="http://127.0.0.1:${HOST_PORT}/health"
NGINX_HEALTH_URL="http://127.0.0.1/health"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

NGINX_SOURCE="${PROJECT_ROOT}/deployment/nginx.conf"
NGINX_DESTINATION="/etc/nginx/conf.d/ridewise-churn-api.conf"

MAX_HEALTH_ATTEMPTS=12
HEALTH_RETRY_DELAY=5


# ------------------------------------------
# Terminal output helpers
# ------------------------------------------

log() {
    echo
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

fail() {
    echo
    echo "DEPLOYMENT FAILED: $1" >&2
    exit 1
}

cleanup_on_error() {
    local exit_code=$?

    echo
    echo "Deployment failed with exit code ${exit_code}." >&2

    if docker ps -a \
        --format '{{.Names}}' \
        | grep -qx "${CONTAINER_NAME}"; then

        echo
        echo "Recent container logs:"
        docker logs --tail 100 "${CONTAINER_NAME}" || true
    fi

    exit "${exit_code}"
}

trap cleanup_on_error ERR


# ------------------------------------------
# Move to project root
# ------------------------------------------

cd "${PROJECT_ROOT}"

log "Project root: ${PROJECT_ROOT}"


# ------------------------------------------
# Confirm operating environment
# ------------------------------------------

if [[ "${EUID}" -eq 0 ]]; then
    fail "Do not run the entire script with sudo. Run it as ec2-user."
fi

if ! command -v docker >/dev/null 2>&1; then
    fail "Docker is not installed. Install and start Docker before deploying."
fi

if ! command -v curl >/dev/null 2>&1; then
    fail "curl is not installed."
fi

if ! command -v nginx >/dev/null 2>&1; then
    fail "Nginx is not installed. Install Nginx before deploying."
fi


# ------------------------------------------
# Confirm Docker is available
# ------------------------------------------

if ! docker info >/dev/null 2>&1; then
    fail "Docker is not running or the current user cannot access Docker.

Try:
    sudo systemctl enable --now docker
    sudo usermod -aG docker ec2-user

Then log out and reconnect to EC2."
fi


# ------------------------------------------
# Confirm required files exist
# ------------------------------------------

log "Checking required deployment files"

REQUIRED_FILES=(
    "Dockerfile"
    "requirements.txt"
    "api/main.py"
    "models/churn_prediction_model.pkl"
    "models/churn_prediction_threshold.pkl"
    "deployment/nginx.conf"
)

for required_file in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "${PROJECT_ROOT}/${required_file}" ]]; then
        fail "Required file is missing: ${required_file}"
    fi

    echo "Found: ${required_file}"
done


# ------------------------------------------
# Display model file sizes
# ------------------------------------------

log "Model files"

ls -lh \
    "${PROJECT_ROOT}/models/churn_prediction_model.pkl" \
    "${PROJECT_ROOT}/models/churn_prediction_threshold.pkl"


# ------------------------------------------
# Build Docker image
# ------------------------------------------

log "Building Docker image ${IMAGE_NAME}:${IMAGE_TAG}"

docker build \
    --pull \
    --tag "${IMAGE_NAME}:${IMAGE_TAG}" \
    "${PROJECT_ROOT}"


# ------------------------------------------
# Stop and remove existing container
# ------------------------------------------

if docker ps \
    --format '{{.Names}}' \
    | grep -qx "${CONTAINER_NAME}"; then

    log "Stopping existing container ${CONTAINER_NAME}"
    docker stop "${CONTAINER_NAME}"
fi

if docker ps -a \
    --format '{{.Names}}' \
    | grep -qx "${CONTAINER_NAME}"; then

    log "Removing existing container ${CONTAINER_NAME}"
    docker rm "${CONTAINER_NAME}"
fi


# ------------------------------------------
# Start new FastAPI container
# ------------------------------------------

log "Starting FastAPI container"

docker run -d \
    --name "${CONTAINER_NAME}" \
    --restart unless-stopped \
    --publish "127.0.0.1:${HOST_PORT}:${CONTAINER_PORT}" \
    --label "application=${APP_NAME}" \
    "${IMAGE_NAME}:${IMAGE_TAG}"


# ------------------------------------------
# Verify container is running
# ------------------------------------------

sleep 3

if ! docker ps \
    --format '{{.Names}}' \
    | grep -qx "${CONTAINER_NAME}"; then

    docker logs "${CONTAINER_NAME}" || true
    fail "The container stopped during startup."
fi

log "Container is running"

docker ps \
    --filter "name=^/${CONTAINER_NAME}$" \
    --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'


# ------------------------------------------
# Wait for FastAPI health check
# ------------------------------------------

log "Waiting for FastAPI health endpoint"

health_passed=false

for attempt in $(seq 1 "${MAX_HEALTH_ATTEMPTS}"); do
    echo "Health-check attempt ${attempt}/${MAX_HEALTH_ATTEMPTS}"

    if curl \
        --silent \
        --show-error \
        --fail \
        "${HEALTH_URL}"; then

        echo
        health_passed=true
        break
    fi

    sleep "${HEALTH_RETRY_DELAY}"
done

if [[ "${health_passed}" != "true" ]]; then
    docker logs --tail 100 "${CONTAINER_NAME}" || true
    fail "FastAPI did not become healthy at ${HEALTH_URL}"
fi

log "FastAPI health check passed"


# ------------------------------------------
# Show application startup logs
# ------------------------------------------

log "Recent FastAPI container logs"

docker logs --tail 50 "${CONTAINER_NAME}"


# ------------------------------------------
# Install Nginx configuration
# ------------------------------------------

log "Installing Nginx configuration"

sudo cp "${NGINX_SOURCE}" "${NGINX_DESTINATION}"
sudo chmod 644 "${NGINX_DESTINATION}"


# ------------------------------------------
# Test Nginx configuration
# ------------------------------------------

log "Testing Nginx configuration"

sudo nginx -t


# ------------------------------------------
# Enable and reload Nginx
# ------------------------------------------

log "Enabling and reloading Nginx"

sudo systemctl enable nginx
sudo systemctl restart nginx


# ------------------------------------------
# Confirm Nginx is running
# ------------------------------------------

if ! sudo systemctl is-active --quiet nginx; then
    sudo systemctl status nginx --no-pager || true
    fail "Nginx is not running."
fi


# ------------------------------------------
# Test API through Nginx
# ------------------------------------------

log "Testing FastAPI through Nginx"

curl \
    --silent \
    --show-error \
    --fail \
    "${NGINX_HEALTH_URL}"

echo


# ------------------------------------------
# Final deployment summary
# ------------------------------------------

PUBLIC_IP="$(curl \
    --silent \
    --max-time 3 \
    http://169.254.169.254/latest/meta-data/public-ipv4 \
    2>/dev/null || true)"

echo
echo "=========================================="
echo "DEPLOYMENT COMPLETED SUCCESSFULLY"
echo "=========================================="
echo
echo "Application container:"
echo "  ${CONTAINER_NAME}"
echo
echo "Docker image:"
echo "  ${IMAGE_NAME}:${IMAGE_TAG}"
echo
echo "Internal FastAPI health endpoint:"
echo "  ${HEALTH_URL}"
echo
echo "Internal Nginx health endpoint:"
echo "  ${NGINX_HEALTH_URL}"
echo

if [[ -n "${PUBLIC_IP}" ]]; then
    echo "Public endpoints:"
    echo "  http://${PUBLIC_IP}/"
    echo "  http://${PUBLIC_IP}/health"
    echo "  http://${PUBLIC_IP}/docs"
    echo "  http://${PUBLIC_IP}/features"
    echo "  http://${PUBLIC_IP}/sample-json"
else
    echo "The EC2 public IP could not be detected automatically."
    echo "Use the Public IPv4 address displayed in the AWS EC2 console."
fi

echo
echo "Useful commands:"
echo "  docker ps"
echo "  docker logs -f ${CONTAINER_NAME}"
echo "  curl ${HEALTH_URL}"
echo "  sudo systemctl status nginx"
echo "  sudo tail -f /var/log/nginx/error.log"
echo
EOF