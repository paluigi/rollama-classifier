# Ollama API Client Helpers

Low-level functions for interacting with the Ollama REST API (native
`/api/chat` endpoint).

## Details

Modern Ollama (\>=v0.12) removed the `/api/tokenize` endpoint and does
not support fill-in-the-middle ("insert") on instruct models. This
module therefore obtains both label tokenization and completion scores
through *empirical forced constrained generation*: it forces a label as
the only valid choice in a `chat()` call and reads back the model's
genuine per-token logprobs. No `/api/tokenize` or `suffix`/insert calls
are used.
