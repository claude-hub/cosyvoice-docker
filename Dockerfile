FROM nvidia/cuda:12.8.1-cudnn-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility
ENV CUDA_VISIBLE_DEVICES=0
ENV CUDA_MODULE_LOADING=LAZY
ENV PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True,max_split_size_mb:128
ENV TORCH_CUDA_ARCH_LIST=12.0
ARG APT_MIRROR=https://mirrors.aliyun.com
ARG PYPI_INDEX=https://mirrors.aliyun.com/pypi/simple/
ARG PYTORCH_INDEX=https://mirror.nju.edu.cn/pytorch/whl/cu128
ARG MINIFORGE_URL=https://mirrors.tuna.tsinghua.edu.cn/github-release/conda-forge/miniforge/LatestRelease/Miniforge3-Linux-x86_64.sh

# Install system dependencies
RUN rm -f /etc/apt/sources.list.d/cuda*.list /etc/apt/sources.list.d/nvidia*.list \
    && printf "deb ${APT_MIRROR}/ubuntu/ jammy main restricted universe multiverse\n\
deb ${APT_MIRROR}/ubuntu/ jammy-updates main restricted universe multiverse\n\
deb ${APT_MIRROR}/ubuntu/ jammy-backports main restricted universe multiverse\n\
deb ${APT_MIRROR}/ubuntu/ jammy-security main restricted universe multiverse\n" > /etc/apt/sources.list \
    && apt-get update && apt-get install -y --no-install-recommends \
    git git-lfs curl wget ffmpeg sox libsox-dev unzip build-essential \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && git lfs install

# Install Miniforge
RUN wget -q ${MINIFORGE_URL} -O /tmp/miniforge.sh \
    && bash /tmp/miniforge.sh -b -p /opt/conda \
    && rm /tmp/miniforge.sh
ENV PATH=/opt/conda/bin:$PATH

# Create conda environment with pynini
RUN conda config --set show_channel_urls yes \
    && conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/conda-forge/ \
    && conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main/ \
    && conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/free/ \
    && conda config --set channel_priority strict \
    && conda create -n cosyvoice python=3.10 -y \
    && conda install -n cosyvoice pynini==2.1.5 -y \
    && conda clean -afy

# Set conda env
ENV CONDA_DEFAULT_ENV=cosyvoice
ENV PATH=/opt/conda/envs/cosyvoice/bin:$PATH
SHELL ["conda", "run", "-n", "cosyvoice", "/bin/bash", "-c"]

WORKDIR /app

# Copy requirements and install
COPY requirements.txt .
ARG PYTORCH_VERSION=2.7.1
ARG PYTORCH_CUDA=cu128
RUN pip install --no-cache-dir \
    torch==${PYTORCH_VERSION}+${PYTORCH_CUDA} \
    torchaudio==${PYTORCH_VERSION}+${PYTORCH_CUDA} \
    --index-url ${PYTORCH_INDEX} \
    --trusted-host=mirrors.aliyun.com

RUN pip install --no-cache-dir -r requirements.txt \
    -i ${PYPI_INDEX} --trusted-host=mirrors.aliyun.com

# Install additional dependencies
RUN pip install --no-cache-dir fastmcp funasr \
    -i ${PYPI_INDEX} --trusted-host=mirrors.aliyun.com

# Copy application code (including third_party with Matcha-TTS)
COPY third_party third_party/
COPY cosyvoice cosyvoice/
COPY asset asset/
COPY app.py mcp_server.py model.py model_paths.py ./

# Set Python path
ENV PYTHONPATH=/app:/app/third_party/Matcha-TTS

# Create data directories
RUN mkdir -p /data/input /data/output

# Environment variables
ENV MODELSCOPE_CACHE=/root/.cache/modelscope
ENV INPUT_DIR=/data/input
ENV OUTPUT_DIR=/data/output
ENV PORT=8188
ENV GPU_IDLE_TIMEOUT=600

EXPOSE 8188

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:${PORT}/health || exit 1

CMD ["conda", "run", "--no-capture-output", "-n", "cosyvoice", "python", "app.py"]
