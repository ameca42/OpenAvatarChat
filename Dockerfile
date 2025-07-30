#FROM nvidia/cuda:12.2.2-cudnn8-devel-ubuntu22.04
FROM nvidia/cuda:12.9.1-cudnn-devel-ubuntu22.04
LABEL authors="HumanAIGC-Engineering"

ARG CONFIG_FILE=config/chat_with_minicpm.yaml

ENV DEBIAN_FRONTEND=noninteractive

# Use Tsinghua University APT mirrors
RUN sed -i 's/archive.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list && \
    sed -i 's/security.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list

# Update package list and install required dependencies
RUN apt-get update && \
    apt-get install -y software-properties-common && \
    add-apt-repository ppa:deadsnakes/ppa && \
    apt-get update && \
    apt-get install -y python3.11 python3.11-dev python3.11-venv python3.11-distutils python3-pip git libgl1 libglib2.0-0

RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 && \
    python3.11 -m ensurepip --upgrade && \
    python3.11 -m pip install --upgrade pip

ARG WORK_DIR=/root/open-avatar-chat
WORKDIR $WORK_DIR

# Install core dependencies
COPY ./install.py $WORK_DIR/install.py
COPY ./pyproject.toml $WORK_DIR/pyproject.toml
COPY ./src/third_party $WORK_DIR/src/third_party



# 配置镜像源
RUN mkdir -p /root/.config/pip && \
    echo "[global]" > /root/.config/pip/pip.conf && \
    echo "index-url = https://pypi.tuna.tsinghua.edu.cn/simple" >> /root/.config/pip/pip.conf

# 配置 uv 镜像源
ENV UV_INDEX_URL="https://pypi.tuna.tsinghua.edu.cn/simple"
ENV UV_EXTRA_INDEX_URL="https://mirrors.aliyun.com/pypi/simple/"

# 配置 uv 重试和超时
ENV UV_HTTP_TIMEOUT=300
ENV UV_CONCURRENT_DOWNLOADS=1
ENV UV_RETRIES=3


# 从本地文件系统读取Python包（使用file://URL方案）
# 注意：需要将Python安装包复制到容器内的/tmp/目录
COPY offline_packages/cpython-3.11.11+20250317-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz /tmp/20250317/
RUN pip install uv && \
    UV_PYTHON_INSTALL_MIRROR="file:///tmp/" \
    uv venv --python 3.11.11 && \
    uv sync --no-install-workspace && \
    rm -f /tmp/cpython-3.11.11+20250317-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz

ADD ./src $WORK_DIR/src

# Copy script files (must be copied before installing config dependencies)
ADD ./scripts $WORK_DIR/scripts

# Execute pre-config installation script
RUN echo "Using config file: ${CONFIG_FILE}"
COPY $CONFIG_FILE /tmp/build_config.yaml
RUN chmod +x $WORK_DIR/scripts/pre_config_install.sh && \
    $WORK_DIR/scripts/pre_config_install.sh --config /tmp/build_config.yaml



# Install config dependencies with retry
RUN for i in 1 2 3; do \
        uv run install.py \
            --config /tmp/build_config.yaml \
            --uv \
            --skip-core && break || sleep 10; \
    done
# Execute post-config installation script
RUN chmod +x $WORK_DIR/scripts/post_config_install.sh && \
    $WORK_DIR/scripts/post_config_install.sh --config /tmp/build_config.yaml && \
    rm /tmp/build_config.yaml

ADD ./resource $WORK_DIR/resource
ADD ./.env* $WORK_DIR/

WORKDIR $WORK_DIR
ENTRYPOINT ["uv", "run", "src/demo.py"]
