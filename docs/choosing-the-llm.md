# Choosing the LLM of the house

**On a Jetson that also runs other services, Qwen3.5 2B at 4 bits, forced whole onto the GPU,
answers a 2,500-token prompt in 3 s.** Qwen3.5 4B (`qwen3.5:4b`) scores better at controlling Home
Assistant, but it did not fit on that Jetson's GPU; on one running only NanoBrain it is still to be
measured. Both see images and call tools, and their accuracy in Home Assistant through Ollama is
still to be measured. This article says why they were picked, how they are measured and what came
out.

## One model for talking and seeing

Home Assistant's [Ollama integration](https://www.home-assistant.io/integrations/ollama/) makes two
entities from the same model:

- A **conversation agent** with the Assist API: Home Assistant hands the model the entities you
  expose and its actions as tools (`HassTurnOn`, `HassLightSet`…), and runs the ones the model
  calls. Assist still answers simple orders itself first, with no LLM.
- An **AI Task** entity that accepts attachments, such as a camera image, and returns structured
  data: "count the cars in the drive" from an automation, answered as a number.

So one multimodal model covers both. Two models do not fit in 8 GB at once, and swapping them costs
a cold load: 30 to 70 s on an Orin Nano, as
[one write-up](https://julien.cloud/blog/jetson-nano-ollama-edge-inference/) measured.

## The candidates

Control is the
[Home LLM Leaderboard](https://github.com/allenporter/home-assistant-datasets/tree/main/reports),
voice orders scored against a synthetic home: `assist` is a medium home (460 cases), `assist-mini`
one with few entities (196). It ran on a desktop GPU with 4-bit models: the accuracy should carry
over to the Jetson, the speed does not.

| Model | Images | Control (`assist` / `assist-mini`) | Why not |
| --- | --- | --- | --- |
| **Qwen3.5 4B** | Yes | 81.1 % / 88.3 % | The candidate |
| Nemotron 3.5 Bolt E4B | No | 85.7 % / 96.9 % | Text only: seeing would take a second model |
| Gemma 4 E4B | Yes | 67.0 % / 91.3 % | 6.6 GB or more to download: no room left for Whisper |
| Gemma 4 E2B | Yes | 45.2 % / 61.2 % | Gets half the orders in a medium home wrong |
| Qwen3.5 2B | Yes | Not scored | The fallback if 4B does not fit |

Figures as published on 2026-11-07. The leaderboard ran Qwen3.5 4B through an OpenAI-compatible
server, not Home Assistant's Ollama integration, so the measurement below repeats it through the
integration a house would use.

## Where the time goes

Every order sends Home Assistant's prompt: its instructions, the exposed entities and the tool
definitions, easily 3,000 to 8,000 tokens. On an Orin Nano, NVIDIA measured
[5.8 s to the first token](https://research.nvidia.com/labs/nemotron/NVIDIA-Nemotron-3.5-Bolt-E4B-4GB/)
for a 4B model with 3,000 tokens in. So the latency of an order is mostly reading that prompt, not
writing the answer, and three things keep it down:

- **Expose few entities.** Home Assistant recommends fewer than 25 for local models.
- **Keep the model loaded.** The integration's default `keep_alive` is forever, and a loaded model
  reuses the part of the prompt that did not change.
- **No thinking.** Qwen3.5 can reason before answering, which adds seconds and helps nothing in a
  short order. The integration's `think` option is off by default: leave it off.

## How it will be measured

On the Jetson, running [`examples/compose.yaml`](../examples/compose.yaml), so memory is what a
house would have.

**Accuracy**: [home-assistant-datasets](https://github.com/allenporter/home-assistant-datasets)
(`docs/eval.md` there has the setup), run from a laptop against the Jetson's Ollama, with a model
file that goes through Home Assistant's own Ollama integration:

```yaml
# models/qwen3.5-4b-ollama.yaml
model_id: qwen3.5-4b-ollama
domain: ollama
config_entry_data:
  url: !secret ollama_url
  model: qwen3.5:4b
config_entry_options:
  llm_hass_api: assist
```

```sh
pytest home_assistant_datasets/tool/assist/collect --models=qwen3.5-4b-ollama \
  --dataset=datasets/assist-mini/ --model_output_dir=reports/assist-mini/jetson
pytest home_assistant_datasets/tool/assist/eval --model_output_dir=reports/assist-mini/jetson
```

**Latency of a real order**: the same run, read from Ollama's own log, which prints how long each
request took: `docker compose logs ollama | grep 'POST "/api/chat"'`. The median and the slowest
tenth are the two numbers that matter.

**Seeing**: one camera snapshot through Ollama's API, with thinking off. Its answer carries
`prompt_eval_duration` (reading the prompt and the image) and `eval_count` over `eval_duration`
(writing speed):

```sh
jq -n --arg image "$(base64 -w0 snapshot.jpg)" '{model: "qwen3.5:4b", stream: false, think: false,
  messages: [{role: "user", content: "How many cars are in the drive?", images: [$image]}]}' |
  curl -s http://jetson.local:11434/api/chat -d @- | jq '{prompt_eval_duration, eval_count, eval_duration}'
```

**Memory**: `ollama ps` for the model, and the Jetson's free memory with both running.

## Results

### First try: a Jetson that also runs other services

**It did not fit on the GPU.** Measured on 2026-11-07 on a Jetson Orin Nano Super 8 GB, L4T R36.4.7,
Ollama 0.40.6 with `JETSON_JETPACK=6`, `qwen3.5:4b` (Q4_K_M, 3.32 GB on disk), thinking off. The
Jetson ran Whisper on the GPU and Piper next to a photo library's machine learning, a network
controller and two agents, which is not a NanoBrain of its own.

| Free memory before loading | Context | Where the model ran | Reading the prompt | Writing |
| --- | --- | --- | --- | --- |
| 2,778 MiB | 4,096 or more | Did not load: `cudaMalloc failed: out of memory` | | |
| 2,778 MiB | 2,048 | 0.72 of 3.39 GiB on the GPU | 25.6 tok/s | 5.6 tok/s |
| 4,212 MiB | 8,192 | 2.1 of 5.37 GiB on the GPU | 32.1 tok/s | 7.0 tok/s |

Speeds from the second run of `ollama run --verbose` with "Turn on the kitchen light"; the first run
spent 35 to 45 s loading the model. Nothing was killed for lack of memory: Ollama put on the CPU
what did not fit on the GPU, and Whisper kept working.

What it means: at 32 tok/s, reading a 3,000-token Assist prompt alone takes over a minute and a
half. A model that spills to the CPU is no use for voice. On a Jetson shared with other services,
a 4B multimodal model with an 8K context needs more memory than it has, so no Home Assistant orders
or image questions were run.

### Second try: Qwen3.5 2B on the same Jetson

**It loaded only after dropping the page cache, and still ran mostly on the CPU.** Measured on
2026-11-09, same Jetson and Ollama, `qwen3.5:2b` (Ollama's default tag, Q8_0, 2.68 GB on disk),
thinking off, nothing else busy.

| Free memory before loading (`MemFree` / `MemAvailable`) | Context | Where the model ran | Reading the prompt | Writing |
| --- | --- | --- | --- | --- |
| 808 / 3,614 MiB | 2,048 to 8,192 | Did not load: `cudaMalloc failed: out of memory` | | |
| 2,930 / 3,269 MiB, after dropping the page cache | 8,192 | 1.0 of 4.7 GiB on the GPU | 39.6 tok/s | 7.1 tok/s |

#### Two lessons on loading a model on a Jetson

- **What counts is free memory, not available memory.** Linux calls page cache "available"
  because it can drop it whenever it likes, but CUDA on a Jetson did not get it back: with 3.6 GB
  available and 0.8 GB free, nothing loaded. Dropping the cache (`sync; echo 3 >
  /proc/sys/vm/drop_caches`) turned "won't load" into "loads". So load the model once, right after
  boot, while memory is free, and keep it loaded: Home Assistant's `keep_alive` already does the
  second half.
- **Ollama splits the model between GPU and CPU by what it sees free, and it is cautious.** With
  2.9 GB free it put only 1 GiB of a 4.7 GiB load on the GPU. A layer on the CPU slows the whole
  model down to CPU speed.

### Third try: Qwen3.5 2B at 4 bits, forced onto the GPU

**It fits whole on the GPU and is fast enough for voice.** Measured on 2026-11-09, same Jetson and
Ollama, `qwen3.5:2b-q4_K_M` with `num_ctx` 8192, thinking off and `num_gpu` 99: the option that
tells Ollama how many layers to put on the GPU, here all of them, instead of its cautious guess.

| Measure | Value |
| --- | --- |
| Where the model ran | 1,380 MiB, all of it on the GPU |
| First load | Failed once (`cudaMalloc failed: out of memory`); the next request loaded it in 13.5 s |
| "Turn on the kitchen light", loaded | Prompt 163.8 tok/s, writing 24.0 tok/s, 2.5 s for 56 tokens |
| A 2,519-token prompt, 20 tokens out | Prompt 1,154 tok/s, 3.0 s in all |
| `MemAvailable` before / loaded / after unloading | 2,996 / 462 / 3,333 MiB |

Fully on the GPU, reading the prompt goes from 40 to over 1,000 tok/s: an Assist prompt takes
seconds, not a minute. Two things to watch:

- **Memory gets tight.** With the model loaded, Ollama's container took 2.74 GiB for a 1.38 GiB
  model. Ollama's `use_mmap` option set to false changed nothing.
- **The first load may fail** while free memory sits in the page cache. Load it once at boot and
  keep it loaded.

Home Assistant's Ollama integration has no `num_gpu` setting, so the option goes into a model of
your own:

```sh
printf 'FROM qwen3.5:2b-q4_K_M\nPARAMETER num_gpu 99\nPARAMETER num_ctx 8192\n' > Modelfile
ollama create qwen3.5-2b-gpu -f Modelfile
```

Home Assistant takes it only by its full name, `qwen3.5-2b-gpu:latest`: without the tag it tries to
download it. Keep only one name loaded: Ollama loads a second copy of the same weights under
another name, and the GPU runs out of memory.

### Fourth try: Qwen3.5 2B as Home Assistant's conversation agent

**Fast, but not reliable: two orders out of six right.** Measured on 2026-11-09 on the same Jetson,
with the model above as a second Ollama conversation agent, the Assist API on and thinking off. Home
Assistant exposed 146 entities, and the orders went straight to the agent through
`conversation.process`.

| Order | Result |
| --- | --- |
| "Enciende la luz de la lavandería" (twice) | Wrong: called no tool, said the light did not exist |
| "Turn on the laundry light" | Right |
| "¿Qué temperatura hace en el salón?" | Right |
| "¿Está abierta la puerta del frigorífico?" | Wrong: said open, naming a sensor that does not exist |
| "Enciende eso" | Right: asked which device, but in English |
| "Apaga la luz de la lavandería" | Failed: called tools in a loop until Home Assistant gave up after 30 s |

Each call to the model took about 2 s, so speed is no longer the problem. The test was harder than a
house would make it, three ways:

- **146 exposed entities**, against the fewer than 25 Home Assistant recommends for local models. A
  2B model gets lost in a prompt that long.
- **Straight to the model.** In a voice pipeline with "prefer handling commands locally", Assist
  answers "turn on the laundry light" itself and the LLM never sees it.
- **No language set.** Without an instruction to answer in Spanish, it answered in English.

#### Where an Orin Nano's memory goes

The containers on that Jetson added up to about 1.3 GB of RAM, yet only 4.4 GB of 7.6 were
available. Read from `/proc/meminfo` and zram's `mm_stat` the same day, the rest was:

| Item | MiB |
| --- | --- |
| Total the kernel manages (of 8 GB: firmware and boot reservations take the rest) | 7,619 |
| Processes' memory (`AnonPages`) | 1,299 |
| Page cache, buffers and swap cache | 876 |
| **zram**: 2,096 MiB of swapped pages, compressed | **851** |
| **CMA in use**: memory the GPU reserved, in no process's RSS | **230** |
| Kernel: slab, vmalloc, page tables, stacks | 318 |
| Not accounted for, likely more GPU allocations | ~172 |

Two lessons for any Jetson:

- **zram is not free.** JetPack swaps to compressed RAM by default. Idle services end up there, out
  of every container's memory figure, and still cost about 0.4 MiB of RAM per MiB they swapped.
- **The GPU's memory is the system's memory**, and no process lists it as its own. To see it, read
  `tegrastats` or `/proc/meminfo`, not `docker stats`.

### On a Jetson running only NanoBrain

| Measure | Qwen3.5 4B |
| --- | --- |
| `assist-mini` accuracy | Not measured yet |
| Order latency, median / slowest tenth | Not measured yet |
| Image question, prompt / writing speed | Not measured yet |
| Memory, model / Jetson free with Whisper | Not measured yet |
