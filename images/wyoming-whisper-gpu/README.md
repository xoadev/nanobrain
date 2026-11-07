# wyoming-whisper-gpu

[wyoming-faster-whisper](https://github.com/rhasspy/wyoming-faster-whisper), Home Assistant's
speech-to-text server, running on the GPU of a Jetson Orin. A short voice order is transcribed in
about 0.6 s instead of 4.4 s on the CPU
([why and how it was measured](../../docs/whisper-on-jetson-gpu.md)).

Upstream publishes CUDA images only for amd64, and PyPI's CTranslate2 wheels for arm64 are CPU only.
This image compiles CTranslate2 with CUDA for the Jetson and ships it on distroless, without cuDNN.

## Run it

Its service in [`examples/compose.yaml`](../../examples/compose.yaml) is the whole setup: the
image, the model arguments, a volume for the models and the GPU.

Then, in Home Assistant, add the **Wyoming Protocol** integration with the Jetson's host and port
`10300`, and pick it as the speech-to-text engine of your Assist pipeline.

The Jetson needs the NVIDIA Container Toolkit, which JetPack installs; `deploy.resources` is how
Compose hands it the GPU.

## Arguments

The entry point already sets `--uri tcp://0.0.0.0:10300`, `--data-dir /data` and `--device cuda`.
Everything in `command` goes to wyoming-faster-whisper:

| Argument | Use |
| --- | --- |
| `--model` | The Whisper model, downloaded to `/data` on first start. `small-int8` is the smallest that gets short orders right in Spanish; `base-int8` if memory is short |
| `--language` | The language spoken, `en`, `es`, `gl`… Leaving it out makes Whisper guess on every phrase |
| `--compute-type int8_float16` | **Always with an int8 model on CUDA**: without it the model is loaded as float16, twice the memory ([why](../../docs/whisper-memory-int8-float16.md)) |

## Volume and port

- **`/data`** holds the downloaded models and every cache. The image runs as the distroless
  `nonroot` user and creates `/data` with that owner, so a **new** volume inherits it. A volume
  first created by another container as root is not writable: give this one its own.
- **`10300`**, Wyoming over TCP, with no authentication: expose it only to your network.
- The health check passes once the model is loaded, which on the first start includes downloading
  it: allow up to five minutes.

## Known limits

- **No `--vad-filter`**: onnxruntime, which only that filter needs, is left out. Home Assistant
  detects the voice itself.
- **Tied to the JetPack.** The build arguments must match the Jetson's L4T and CUDA (`cat
  /etc/nv_tegra_release`): `L4T_TAG` with its digest, and `CUDA_ARCH` (`8.7` is Orin).
- **Memory comes from the shared 8 GB** and counts towards the container's memory limit, GPU
  included. Measure it after a few phrases, not at rest: `small-int8` settles near 600 MiB.

## How it is built

Three stages, so only the last one ships:

1. **`library`**, on NVIDIA's `l4t-jetpack`, compiles CTranslate2's C++ library with CUDA. The
   JetPack image is 5.6 GB compressed and is never shipped.
2. **`python`**, on Debian, builds the Python bindings and installs the locked dependencies into a
   virtualenv. It uses the same Debian release, and so the same Python, as the distroless stage:
   the virtualenv links to `/usr/bin/python3`, and still works once copied.
3. **The final stage**, distroless with no shell or package manager, holds the library, cuBLAS and
   the virtualenv. The CUDA driver comes from the Jetson.

[`check.py`](check.py) runs inside the built image with no GPU and decodes a WAV, as every
transcription does, so a library missing from the distroless stage fails in CI, not on the Jetson.

`requirements.txt` and `build-requirements.txt` are locked with hashes by
`uv pip compile`; the command is in their header.
