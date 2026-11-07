# Choosing the LLM of the house

The candidate is **Qwen3.5 4B** (`qwen3.5:4b` in Ollama): of the models that fit next to Whisper in
the Jetson's 8 GB, it is the only one that sees images, calls tools and scores well at controlling
Home Assistant. **It has not been measured on the Jetson yet**: this article says why it was picked
and how it will be measured, and its results table fills in when it is.

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

| Measure | Qwen3.5 4B |
| --- | --- |
| `assist-mini` accuracy | Not measured yet |
| Order latency, median / slowest tenth | Not measured yet |
| Image question, prompt / writing speed | Not measured yet |
| Memory, model / Jetson free with Whisper | Not measured yet |
