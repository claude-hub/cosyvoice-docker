#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}🎙️ CosyVoice Docker Launcher${NC}"
echo "================================"

# Check nvidia-docker
NVIDIA_SMI=$(command -v nvidia-smi || true)
if [ -z "$NVIDIA_SMI" ] && [ -x /usr/lib/wsl/lib/nvidia-smi ]; then
    NVIDIA_SMI=/usr/lib/wsl/lib/nvidia-smi
fi

if [ -z "$NVIDIA_SMI" ]; then
    echo -e "${RED}❌ nvidia-smi not found. Please install NVIDIA drivers.${NC}"
    exit 1
fi

if ! docker info 2>/dev/null | grep -q "Runtimes.*nvidia"; then
    echo -e "${YELLOW}⚠️ nvidia-docker runtime not detected. GPU support may not work.${NC}"
fi

# Fixed target: RTX 5060 Ti 16G on host GPU 0
echo -e "${YELLOW}🔍 Checking GPU 0...${NC}"
GPU_ID=0

if ! "$NVIDIA_SMI" -i $GPU_ID > /dev/null 2>&1; then
    echo -e "${RED}❌ GPU 0 not detected${NC}"
    exit 1
fi

GPU_NAME=$("$NVIDIA_SMI" --query-gpu=name --format=csv,noheader -i $GPU_ID)
GPU_MEM=$("$NVIDIA_SMI" --query-gpu=memory.used,memory.total --format=csv,noheader -i $GPU_ID)
echo -e "${GREEN}✅ Using GPU $GPU_ID: $GPU_NAME ($GPU_MEM)${NC}"

export NVIDIA_VISIBLE_DEVICES=all
export CUDA_VISIBLE_DEVICES=0

# Load .env if exists
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

MODELSCOPE_CACHE=${MODELSCOPE_CACHE:-$HOME/.cache/modelscope}
if [ ! -d "$MODELSCOPE_CACHE" ]; then
    echo -e "${RED}❌ MODELSCOPE_CACHE does not exist: $MODELSCOPE_CACHE${NC}"
    echo -e "${YELLOW}   Set MODELSCOPE_CACHE in .env to the directory used by 'modelscope download'.${NC}"
    exit 1
fi
export MODELSCOPE_CACHE

# Default port
PORT=${PORT:-8188}

# Check port availability
check_port() {
    if ss -tlnp 2>/dev/null | grep -q ":$1 "; then
        return 1
    fi
    return 0
}

if ! check_port $PORT; then
    echo -e "${YELLOW}⚠️ Port $PORT is in use, finding available port...${NC}"
    for p in $(seq 8188 8250); do
        if check_port $p; then
            PORT=$p
            break
        fi
    done
fi

export PORT
echo -e "${GREEN}📡 Using port: $PORT${NC}"

# Create data directories
mkdir -p /tmp/cosyvoice/input /tmp/cosyvoice/output /tmp/cosyvoice/voices

# Start
echo -e "${YELLOW}🚀 Starting service...${NC}"
docker compose up -d

# Wait for health check
echo -e "${YELLOW}⏳ Waiting for service to be ready...${NC}"
for i in {1..60}; do
    if curl -sf http://localhost:$PORT/health > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Service is ready!${NC}"
        break
    fi
    sleep 2
    echo -n "."
done

echo ""
echo "================================"
echo -e "${GREEN}🎉 CosyVoice is running!${NC}"
echo ""
echo -e "  UI:      ${GREEN}http://0.0.0.0:$PORT${NC}"
echo -e "  API:     ${GREEN}http://0.0.0.0:$PORT/docs${NC}"
echo -e "  Health:  ${GREEN}http://0.0.0.0:$PORT/health${NC}"
echo ""
echo -e "  Input:   /tmp/cosyvoice/input"
echo -e "  Output:  /tmp/cosyvoice/output"
echo ""
echo -e "  GPU:     $GPU_ID ($GPU_NAME)"
echo ""
echo "Commands:"
echo "  docker compose logs -f    # View logs"
echo "  docker compose down       # Stop service"
echo "================================"
