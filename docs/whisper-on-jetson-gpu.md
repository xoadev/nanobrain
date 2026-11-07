# Whisper on the GPU of a Jetson

Moving Whisper from the Jetson's CPU to its GPU cut the transcription of a short voice order from
4.4 s to 0.6 s, which is the difference between a voice assistant that answers and one you repeat
yourself to. Getting there means compiling one library, because nobody publishes it for this
machine.

## The measurement

| | CPU | GPU |
| --- | --- | --- |
| Speech to text of a short order | 4.4 s | 0.6 s |

- **Hardware**: Jetson Orin Nano Super, 8 GB, JetPack 6.2 (L4T R36.4.7, CUDA 12.6).
- **Software**: wyoming-faster-whisper 3.8.1 with the `small-int8` model, Spanish. CPU: upstream's
  `rhasspy/wyoming-whisper` image. GPU: the first build of this image, which still carried cuDNN.
- **Date**: 2026-11-07.
- **Method**: the same spoken orders through Home Assistant's Assist, reading the speech-to-text
  time of each run in the pipeline's debug view.

To repeat it, point two Assist pipelines at the two servers and compare that time for the same
orders. A first run after start includes loading the model: discard it.

## Why it has to be compiled

Whisper does not run on its own here. [faster-whisper](https://github.com/SYSTRAN/faster-whisper),
which wyoming-faster-whisper uses, runs the model on
[CTranslate2](https://github.com/OpenNMT/CTranslate2), a C++ inference engine. CTranslate2 is what
talks to CUDA, and its wheels on PyPI for arm64 are built for the CPU only. Upstream's Wyoming image
has CUDA only for amd64.

So the image compiles CTranslate2 itself, on NVIDIA's `l4t-jetpack` image, which carries `nvcc` and
the CUDA libraries matching the Jetson's JetPack. Two details matter:

- **The architecture**: `CUDA_ARCH=8.7` is Orin. Compiling for one architecture only is what keeps
  the build in about 10 minutes.
- **No GPU needed to build**: `nvcc` produces the GPU code on any arm64 machine, so GitHub's
  `ubuntu-24.04-arm` runners build the image. Whether it actually runs on the GPU, only the Jetson
  can tell.

## What it costs

The GPU shares the Jetson's 8 GB with everything else, the LLM included. The first build of this
image was 10.3 GB and used 1.7 GiB of memory; the next two articles bring it down to
[831 MB](whisper-image-size.md) and [589 MiB](whisper-memory-int8-float16.md).
