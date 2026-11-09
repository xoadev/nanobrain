# AGENTS.md

You are a lazy senior developer. Lazy means efficient, not careless. The best code is the code never
written.

Before writing any code, stop at the first rung that holds:

1. Does this need to be built at all? (YAGNI)
2. Does the standard library already do this? Use it.
3. Does a native platform feature cover it? Use it.
4. Does an already-installed dependency solve it? Use it.
5. Can this be one line? Make it one line.
6. Only then: write the minimum code that works.

Rules:

- No abstractions, dependencies or boilerplate nobody asked for.
- Deletion over addition. Boring over clever. Fewest files possible.
- Question complex requests: "Do you actually need X, or does Y cover it?"
- Same size, pick the edge-case-correct option: lazy means less code, not the flimsier algorithm.
- Mark intentional shortcuts with a `ponytail:` comment that names the ceiling and the upgrade path.

Not lazy about: input validation at trust boundaries, error handling that prevents data loss,
security, accessibility, anything explicitly requested. Non-trivial logic leaves ONE runnable check
behind, the smallest thing that fails if the logic breaks. Trivial one-liners need no test.

---

## Languages

- **Everything in the repository is in English**: code, comments, logs, errors, commits and
  documentation. It is open source, and English is what its readers share.
- **The agent answers in the language it is spoken to.**
- **What a machine reads is never translated**: Conventional Commits, `Closes #12`, JSON keys.

## Code

- **Code reads aloud**: descriptive names, small functions with one responsibility, named constants,
  explicit types on public interfaces and explicit errors (no silent `catch`).
- **Minimal comments, only for what the code cannot say**: the why, an invariant, a trap, a ceiling
  (`ponytail:`). If a comment explains what the code does, the problem is the code: rewrite it and
  delete the comment.
- **Nothing is written twice, neither code nor documentation.** Before writing, look for the
  component, helper or validator that already exists. Repeated logic is extracted into a shared
  component whose name says its intent. A fact lives in one place and the rest link to it, they do
  not copy it.
- **Composition over inheritance or copying**, and small interfaces that hide their details.
- **Errors say what to do**: `no SSH key at /data/id_ed25519 ([ssh].identity in limen.toml)`, not
  `file not found`.
- No `TODO` in the code: what is pending goes to an issue.
- **Secrets stay out of the repository**: not in code, logs or error messages. What is committed
  encrypted says so in its name, and a check proves it is.

## Commands and checks

- **Everything runs through `make`**: build, lint, tests, deploy. CI calls the same targets, so what
  is checked is defined once and cannot drift from a laptop. If no target covers what you need, add
  the target; do not run it by hand.
- **Every repository has `make lint` and `make test`, and CI runs them on every pull request**, at
  least over what the pull request touches. A repository without them adds them before its next
  feature. `make lint` green before pushing.
- **Strict linters**: the stack's official ones, with warnings as errors, and the cross-cutting ones
  for the files there are (shellcheck, actionlint, markdownlint, typos). When one needs a runtime
  the repository does not use, its ecosystem's equivalent with the same rules will do (rumdl instead
  of markdownlint in Rust). The formatter, no debate.
- **A change in behaviour comes with its test in the same pull request**, and a fixed bug with the
  test that reproduces it. Integration tests over real flows are the base; unit tests only where
  they pay off (domain, parsers, state machines).
- **A check is never disabled or relaxed** to make it green. A silenced lint carries its reason on
  the same line. If something outside the change keeps it red, say so in the pull request.
- **A test documents a behaviour and fails when the promise breaks**: break the code on purpose and
  watch it go red. No tests to fill coverage.

## Dependencies

- **Only if they are alive, used, and make sense.** Alive: recent releases and maintainers who
  answer. Used: wide adoption. Make sense: they are worth their weight against the lines they save.
  No open security advisories.
- **Pinned versions, at least a week old**: an exact version, never a range or `latest`; actions by
  SHA with the version in a comment. Dependabot with the same cooldown.
- **Node through pnpm**, never npm or yarn: its version pinned in `package.json`'s `packageManager`;
  `pnpm install --frozen-lockfile` in CI; a one-week `minimumReleaseAge`, and install scripts only
  for the packages that need them.
- **Python through uv**: the Python version and dependencies pinned in `uv.lock`, with hashes;
  `uv sync --frozen` in CI, and `uvx` with an exact version for standalone tools.
- In workflows, secrets and `${{ }}` values reach `run:` through `env:`, never interpolated, and the
  token only reads unless the job asks for more.

## Spec, documentation and knowledge

- **The spec is the source of truth.** If the code has to diverge, the spec changes first. A
  contradiction between spec, documentation and code is raised before acting; no side is picked in
  silence.
- **What is published only grows, once there is production**: in an API, a schema, an event or a
  format real users already rely on, things are added, never removed or renamed. Breaking it is a
  task to prepare, not a change in a pull request. While a project is in testing or has no users,
  break what is needed; the repository says in its own part which of the two it is in.
- **Documentation is updated in the same pull request** that makes it wrong. Before the commit,
  search for what the change contradicts (the old name, the old behaviour), not only for where the
  new thing goes.
- **No version numbers in the documentation**: examples say `X.Y.Z`. A number written down is wrong
  at the next release.
- **What an agent learns is written in the repository** (its `AGENTS.md`, a skill or `docs/`), never
  only in its private memory: the next session, another agent or a person cannot read it. A mistake
  already made is written down with what avoids it.

## Git and pull requests

- **Nothing goes straight to `main`**: everything through a pull request. Branches `feat/`, `fix/`
  and `chore/` from `origin/main`, in a worktree of your own: never in the person's checkout nor on
  a local `main`, which may lag behind.
- **Work iterates on one branch** while it is being built and tried: new work goes to the branch and
  the pull request already open. **A new pull request is opened only when asked for.**
- **Squash is the only merge strategy**: the pull request title becomes the commit subject and its
  description, the body. The description explains the why in a couple of paragraphs; it does not
  list the diff.
- **Before pushing**: rebase on the remote and get build, lint and tests green on that tree. The
  check that decides a push has no pipes: `| tail` exits 0 even when it fails.
- With several changes queued, no push and no full suites per change until told.

## How to talk to whoever asked for the work

- **Technical and concise.** The conclusion first, then the why, in short sentences, with no
  preamble and no tour of the options left out.
- **When done, or when you need an answer, close with a brief summary**: what is done and verified,
  what failed or was skipped, and what the person has to decide or do. If nothing, say so.
- **Report with evidence**: "done" comes with the output that proves it, and what was not verified
  is said to be unverified. A skipped check is not a passing one.
- A question comes with its recommendation and just enough to answer it without reading the rest.
- Before a large change, summarize the plan and wait for confirmation.

## For agents

- **What cannot be undone needs explicit confirmation**: a deploy, a migration, deleting data,
  touching a machine. Production is deployed only from CI, never from a branch or by hand.
- Waits end on their own: no `until pgrep` loops and no `tail -f` until the timeout.
- Untrusted code (someone else's builds or tests) runs with a memory cap (`ulimit -d`).

---

This block is shared by the open source repositories of XOA Desarrollo and its source is
<https://xoa.dev/_dev/OSS_AGENTS.md>: it changes there, never in a repository's copy, and
`make agents-sync` brings it in. What belongs to each repository goes below and prevails where it
narrows what is above.
<!-- xoadev:end -->

## 1. What NanoBrain is

Container images and articles that turn an NVIDIA Jetson Orin Nano into the local brain of a
Home Assistant home: hearing, speaking, understanding and seeing, with no cloud. The
[README](README.md) is the overview; each image's `README.md` is its reference.

**Stage: in testing, no users yet.** Published tags may still be withdrawn; once a tag is pulled by
people outside XOA, what is published only grows.

## 2. Tone

The repository teaches. A reader who knows Docker but has never touched a Jetson should finish a
README or an article knowing **why** each decision was taken, not only what to type.

- Lead with the outcome, then the reason, then the command. Explain a term the first time it
  appears (Wyoming, L4T, int8) in half a sentence, or link to where it is explained.
- **Every figure carries its context**: date, hardware, image version and how it was measured, so
  anyone can repeat it. An estimate says it is one.
- Nothing about a particular home: no IPs, entity names, secrets or private repositories. Examples
  use `homeassistant.local` and the defaults.

## 3. Images

- One folder per image in `images/<name>/`: `Dockerfile`, its locks, `check.py` and `README.md`.
- **Each image has its own version, from convco**: the conventional commits that touched
  `images/<name>/` since its last tag `<name>-vX.Y.Z` say the next one (`feat` minor, `fix` patch,
  `!` major). Run by hand from `main`, `release.yaml` publishes it to
  `ghcr.io/xoadev/nanobrain/<name>:X.Y.Z` and makes the release with its changelog; a published tag
  is never rewritten. So the pull request's title, the squash commit, is what versions the image:
  `fix(wyoming-whisper-gpu): …` for a new lock, `feat(…)` for a new capability, and a type that does
  not release (`docs`, `chore`) only for what does not change the image.
- **`check.py` runs inside the image, with no GPU**, and does what each real request does (Whisper
  decodes a WAV). A server that starts is not enough: a health check does not exercise the code
  path that breaks.
- **An image is added only when no maintained one serves.** What a project already publishes for
  the Jetson (Ollama, Piper) is documented, not rebuilt.
- Bases pinned by digest; Python dependencies locked with hashes (`uv pip compile
  --generate-hashes`, a week back) and installed with `--only-binary :all:`.
- Compiling CUDA needs `nvcc`, not a GPU: images build on GitHub's `ubuntu-24.04-arm` runners. Only
  the Jetson can tell whether they run on its GPU; say so when a change has not been tried there.

## 4. Articles

One per decision in [`docs/`](docs/), listed in its [README](docs/README.md). Written from what was
measured, with the numbers in a table and how to repeat them.
