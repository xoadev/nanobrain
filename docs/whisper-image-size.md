# From 10.3 GB to 831 MB

The first GPU Whisper image was 10.3 GB; the published one is 831 MB, with the same speed. Most of
the weight was a build environment shipped by accident, and a library CTranslate2 no longer needs.

## The measurement

| Build | Image size |
| --- | --- |
| First build: runs on `l4t-jetpack`, with cuDNN and onnxruntime | 10.3 GB |
| Three stages, final one on distroless, no cuDNN or onnxruntime | 831 MB |

Measured on 2026-11-07 on a Jetson Orin Nano Super, JetPack 6.2, as the size Docker reports for the
image once built.

## Where the gigabytes went

1. **The JetPack image itself.** `l4t-jetpack` carries the whole CUDA toolkit, compilers included:
   5.6 GB compressed. It is needed to compile, not to run. A multi-stage Dockerfile compiles in one
   stage and copies only the result into the next; nothing else of the first stage ships.
2. **cuDNN, near 1 GB.** Whisper uses cuDNN only for its convolution layers, and CTranslate2 has had
   its own CUDA Conv1D since 4.6.3, so the build passes `-DWITH_CUDNN=OFF`. What CUDA the image
   still loads at run time is cuBLAS; the CUDA runtime is linked statically and the driver comes
   from the Jetson.
3. **onnxruntime and its dependencies.** faster-whisper needs it only for its voice-activity filter
   (`--vad-filter`), which is off by default. Home Assistant already detects when the voice stops,
   so the lock leaves it out.
4. **A full OS.** The final stage is
   [distroless](https://github.com/GoogleContainerTools/distroless): Python and its libraries, no
   shell, no package manager, running as `nonroot`.

## The trap in copying a virtualenv

A virtualenv is not self-contained: its `python3` is a link to the interpreter it was created with,
`/usr/bin/python3`. Built on one distribution and copied to another, it links to a Python that is
not there, or not the same. So the stage that builds the virtualenv runs on the same Debian release
as the distroless image, and the same Python.

## How to check an image this small still works

Distroless has no shell, so nothing can be tried by hand inside it. The image's
[`check.py`](../images/wyoming-whisper-gpu/check.py) runs with its own Python, with no GPU: it
imports the server and decodes a WAV, as each transcription does. That is what caught the one
regression of this work: a newer PyAV that faster-whisper could no longer call. The server started
and passed its health check, and every transcription failed. The health check never decodes audio;
the check does.
