# From 1.7 GiB to 589 MiB

With an int8 model on CUDA, wyoming-faster-whisper needs `--compute-type int8_float16`. Without
it, the model is loaded as float16 and takes about twice the memory, on a machine where the GPU
shares 8 GB with the language model.

## The measurement

| Build and flags | Memory after use |
| --- | --- |
| First build, no `--compute-type` | 1.7 GiB of its 2 GiB limit |
| Published build, `--compute-type int8_float16` | 589 MiB |

Measured on 2026-11-07 on a Jetson Orin Nano Super, JetPack 6.2, with the `small-int8` model, as
the container's memory in `docker stats` after a few transcriptions. The two rows also differ in the
build (the second has no cuDNN or onnxruntime), so the flag is not the whole of the drop.

Measure after use, not at rest: the model and CUDA's buffers are allocated on the first
transcription, and at rest the number looks better than what the container will need.

## Why the flag matters

A model's weights can be stored and computed in different number formats. `int8` stores each weight
in one byte; `float16` in two. A model named `small-int8` is stored as int8, but the format it is
computed in is chosen when it is loaded. Without `--compute-type`, wyoming-faster-whisper picks
float16 on CUDA, so the int8 weights are converted on load and take twice the room.

`int8_float16` keeps the weights in int8 and does the arithmetic that needs more precision in
float16, which the Jetson's GPU does fast.

## Why memory counts twice on a Jetson

A desktop GPU has its own memory. The Jetson's GPU does not: CPU and GPU share the same 8 GB, and
what the GPU allocates counts towards the container's memory limit. Every megabyte Whisper takes is
one the language model, the biggest piece of the house, does not get.
