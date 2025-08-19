FROM ubuntu:22.04

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    curl \
    wget \
    unzip \
    pkg-config \
    libasound2-dev \
    libx11-dev \
    libxrandr-dev \
    libxinerama-dev \
    libxcursor-dev \
    libfreetype6-dev \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js and npm
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install Dart SDK
RUN ARCH=$(dpkg --print-architecture) && \
    wget -qO- https://dl-ssl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/dart.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/dart.gpg arch=${ARCH}] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main" | tee /etc/apt/sources.list.d/dart_stable.list && \
    apt-get update && \
    apt-get install -y dart && \
    rm -rf /var/lib/apt/lists/*

# Set user for development first
RUN useradd -m -s /bin/bash vscode && \
    echo "vscode ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Install Flutter and fix ownership
RUN git clone https://github.com/flutter/flutter.git -b stable /opt/flutter && \
    chown -R vscode:vscode /opt/flutter && \
    sudo -u vscode /opt/flutter/bin/flutter doctor

# Add Dart and Flutter to PATH
ENV PATH="/usr/lib/dart/bin:/opt/flutter/bin:${PATH}"

# Create workspace directory
WORKDIR /workspace

# Set VST3_SDK_DIR environment variable
ENV VST3_SDK_DIR=/workspace/vst3sdk

# Create workspace directory
WORKDIR /workspace

# Install Claude Code globally
RUN npm install -g @anthropic-ai/claude-code

USER vscode
WORKDIR /workspace