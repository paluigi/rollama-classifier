# Inference backends for rollama

Each backend provides a unified interface with `chat()`, `score()`, and
`tokenize()` methods, plus a `supports_bare_label_constraint` capability
flag. Backends communicate via HTTP using the OpenAI-compatible API
(vLLM, SGLang, llama.cpp) or the native API (Ollama).
