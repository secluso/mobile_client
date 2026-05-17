# Pinned ubuntu (index digest as of 2026-04-10)
FROM ubuntu:24.04@sha256:c4a8d5503dfb2a3eb8ab5f807da5bc69a85730fb49b5cfca2330194ebcc41c7b

ARG DEBIAN_FRONTEND=noninteractive
# Ubuntu archive snapshot. Pins every apt package across builder rebuilds. 
ARG UBUNTU_SNAPSHOT=20260501T000000Z
ARG FLUTTER_REVISION=8defaa71a77c16e8547abdbfad2053ce3a6e2d5b
ARG RUST_TOOLCHAIN=1.90.0
ARG BUNDLETOOL_VERSION=1.18.2
ARG ANDROID_CMDLINE_TOOLS_ZIP=commandlinetools-linux-11076708_latest.zip
ARG ANDROID_BUILD_TOOLS=35.0.0
ARG ANDROID_PLATFORM=android-35
ARG ANDROID_BUILD_TOOLS_COMPAT=34.0.0
ARG ANDROID_PLATFORM_31=android-31
ARG ANDROID_PLATFORM_33=android-33
ARG ANDROID_PLATFORM_34=android-34
ARG ANDROID_PLATFORM_36=android-36
ARG ANDROID_NDK=27.0.12077973
ARG ANDROID_CMAKE=3.22.1

ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV CARGO_HOME=/opt/cargo
ENV BUNDLETOOL_JAR=/opt/bundletool.jar
ENV FLUTTER_HOME=/opt/flutter
ENV GRADLE_USER_HOME=/opt/gradle-home
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV PUB_CACHE=/opt/pub-cache
ENV RUSTUP_HOME=/opt/rustup
ENV PATH=/opt/flutter/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:/opt/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Bootstrap TLS trust from the base image's default (http, GPG-verified) apt sources first...
# snapshot.ubuntu.com forces https and the minimal ubuntu base does not include ca-certificates.
# ca-certificates is reinstalled from the pinned snapshot below, so the final installed version is still deterministic
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates; \
    rm -rf /var/lib/apt/lists/*

# Repoint apt at the pinned Ubuntu snapshot before any update/install
RUN set -eux; \
    : "${UBUNTU_SNAPSHOT:?missing UBUNTU_SNAPSHOT build arg}"; \
    codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"; \
    snap="https://snapshot.ubuntu.com/ubuntu/${UBUNTU_SNAPSHOT}"; \
    rm -f /etc/apt/sources.list.d/ubuntu.sources; \
    { \
    echo "deb ${snap} ${codename} main universe"; \
    echo "deb ${snap} ${codename}-updates main universe"; \
    echo "deb ${snap} ${codename}-security main universe"; \
    } > /etc/apt/sources.list; \
    printf 'Acquire::Check-Valid-Until "false";\nAcquire::Retries "8";\n' \
    > /etc/apt/apt.conf.d/99snapshot

RUN apt-get update \
    && apt-get install -y \
    build-essential \
    ca-certificates \
    clang \
    curl \
    file \
    git \
    openjdk-17-jdk \
    pkg-config \
    python3 \
    rsync \
    unzip \
    xz-utils \
    zip \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/android-sdk/cmdline-tools \
    && curl -fsSL "https://dl.google.com/android/repository/${ANDROID_CMDLINE_TOOLS_ZIP}" -o /tmp/android-tools.zip \
    && unzip -q /tmp/android-tools.zip -d /opt/android-sdk/cmdline-tools \
    && mv /opt/android-sdk/cmdline-tools/cmdline-tools /opt/android-sdk/cmdline-tools/latest \
    && yes | sdkmanager --licenses >/dev/null \
    && sdkmanager \
    "build-tools;${ANDROID_BUILD_TOOLS}" \
    "build-tools;${ANDROID_BUILD_TOOLS_COMPAT}" \
    "cmake;${ANDROID_CMAKE}" \
    "ndk;${ANDROID_NDK}" \
    "platform-tools" \
    "platforms;${ANDROID_PLATFORM}" \
    "platforms;${ANDROID_PLATFORM_31}" \
    "platforms;${ANDROID_PLATFORM_33}" \
    "platforms;${ANDROID_PLATFORM_34}" \
    "platforms;${ANDROID_PLATFORM_36}" \
    && rm -f /tmp/android-tools.zip

RUN curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain "${RUST_TOOLCHAIN}" \
    && rustup target add \
    --toolchain "${RUST_TOOLCHAIN}" \
    aarch64-linux-android \
    armv7-linux-androideabi \
    i686-linux-android \
    x86_64-linux-android

RUN curl -fsSL \
    "https://github.com/google/bundletool/releases/download/${BUNDLETOOL_VERSION}/bundletool-all-${BUNDLETOOL_VERSION}.jar" \
    -o /opt/bundletool.jar

RUN git clone https://github.com/flutter/flutter.git /opt/flutter \
    && cd /opt/flutter \
    && git checkout "${FLUTTER_REVISION}" \
    && flutter config --no-analytics \
    && dart --disable-analytics \
    && flutter precache --android

WORKDIR /workspace
