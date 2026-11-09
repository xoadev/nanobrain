# Articles

One article per decision, each with the numbers measured on the Jetson and how to repeat them.

| Article | Decision |
| --- | --- |
| [Whisper on the GPU of a Jetson](whisper-on-jetson-gpu.md) | Compile CTranslate2 with CUDA, because no published build has it for arm64 |
| [From 10.3 GB to 831 MB](whisper-image-size.md) | Ship on distroless, without cuDNN or onnxruntime |
| [From 1.7 GiB to 589 MiB](whisper-memory-int8-float16.md) | Always pass `--compute-type int8_float16` |
| [Choosing the LLM of the house](choosing-the-llm.md) | Qwen3.5, one model that talks and sees: 2B at 4 bits fits a shared Jetson's GPU |

Every figure carries its date, hardware, image and method. An estimate says it is one.
