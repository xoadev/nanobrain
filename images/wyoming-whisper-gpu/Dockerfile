# Wyoming's faster-whisper on the Jetson's GPU. PyPI's CTranslate2 wheels for arm64 are CPU only, so it is compiled
# here with CUDA. Three stages, so only the last one ships: JetPack compiles the C++ library, Debian builds the Python
# side against the distroless image's own Python, and distroless runs it with no shell nor package manager.
#
# The JetPack must match the machine's L4T and CUDA (`cat /etc/nv_tegra_release` on the Jetson): for another one,
# change L4T_TAG, its digest and CUDA_ARCH. Debian and distroless go together: the virtualenv points at the same
# /usr/bin/python3.
ARG L4T_TAG=r36.4.0
FROM nvcr.io/nvidia/l4t-jetpack:${L4T_TAG}@sha256:34ccf0f3b63c6da9eee45f2e79de9bf7fdf3beda9abfd72bbf285ae9d40bb673 AS library

# 8.7 is Orin.
ARG CUDA_ARCH=8.7
ARG CTRANSLATE2_VERSION=4.8.4
ARG CTRANSLATE2_COMMIT=5de572ef60b67a0276c5989ee73d0072808ff4c3
# Each nvcc job takes over 1 GB: 3 still builds on the Jetson's own 8 GB, as well as on GitHub's arm64 runner.
ARG BUILD_JOBS=3

# hadolint ignore=DL3008 # the pin is the base's digest: a pinned apt version breaks once the archive drops it
RUN apt-get update \
    && apt-get install -y --no-install-recommends cmake git \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch "v${CTRANSLATE2_VERSION}" --recurse-submodules --shallow-submodules \
        https://github.com/OpenNMT/CTranslate2.git /src \
    && test "$(git -C /src rev-parse HEAD)" = "${CTRANSLATE2_COMMIT}"

# Without cuDNN, which is near 1 GB: CTranslate2 has its own CUDA Conv1D, Whisper's only use of it. No MKL on arm64:
# Ruy does the CPU's int8, OpenMP from GCC. cuBLAS is all CUDA it loads at run time (cudart is static); the driver
# comes from the machine.
RUN cmake -S /src -B /src/build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/opt/ctranslate2 \
        -DWITH_CUDA=ON -DWITH_CUDNN=OFF -DCUDA_ARCH_LIST="${CUDA_ARCH}" \
        -DWITH_MKL=OFF -DWITH_RUY=ON -DOPENMP_RUNTIME=COMP -DBUILD_CLI=OFF \
    && cmake --build /src/build -j "${BUILD_JOBS}" \
    && cmake --install /src/build \
    && cp -a /usr/local/cuda/lib64/libcublas.so.12* /usr/local/cuda/lib64/libcublasLt.so.12* /opt/ctranslate2/lib/

FROM debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2 AS python

# hadolint ignore=DL3008 # the pin is the base's digest: a pinned apt version breaks once the archive drops it
RUN apt-get update \
    && apt-get install -y --no-install-recommends g++ python3-dev python3-venv \
    && rm -rf /var/lib/apt/lists/*

COPY --from=library /opt/ctranslate2 /opt/ctranslate2
COPY --from=library /src/python /src/python
COPY build-requirements.txt requirements.txt /tmp/
WORKDIR /src/python
RUN python3 -m venv /opt/build-venv \
    && /opt/build-venv/bin/pip install --no-cache-dir --require-hashes --only-binary :all: -r /tmp/build-requirements.txt \
    && CTRANSLATE2_ROOT=/opt/ctranslate2 /opt/build-venv/bin/python setup.py bdist_wheel --dist-dir /wheels

RUN python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir --no-deps /wheels/*.whl \
    && /opt/venv/bin/pip install --no-cache-dir --no-deps --require-hashes --only-binary :all: -r /tmp/requirements.txt \
    && mkdir /data

FROM gcr.io/distroless/python3-debian13:nonroot@sha256:1c32c3720dc4c7f0c7dbe998737f32c200add6511eca7cec705008be488b87d6

LABEL org.opencontainers.image.source=https://github.com/xoadev/nanobrain \
      org.opencontainers.image.description="Wyoming faster-whisper on the GPU of a Jetson Orin" \
      org.opencontainers.image.licenses=Apache-2.0

COPY --from=library /opt/ctranslate2/lib /opt/ctranslate2/lib
COPY --from=python /opt/venv /opt/venv
# A new volume takes this directory's owner, so nonroot can write the models into it.
COPY --from=python --chown=nonroot:nonroot /data /data
ENV LD_LIBRARY_PATH=/opt/ctranslate2/lib
# As upstream's image: every cache on the volume, not in the container.
ENV HF_HOME=/data XDG_CACHE_HOME=/data

EXPOSE 10300
# The server listens only once the model is loaded, downloading it on the first start.
HEALTHCHECK --interval=30s --timeout=20s --start-period=5m --retries=3 \
    CMD ["/opt/venv/bin/python3", "-m", "wyoming_faster_whisper.health_check"]

ENTRYPOINT ["/opt/venv/bin/python3", "-m", "wyoming_faster_whisper", \
    "--uri", "tcp://0.0.0.0:10300", "--data-dir", "/data", "--device", "cuda"]
