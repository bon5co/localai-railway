# localai-railway

Wrapper image for deploying [LocalAI](https://github.com/mudler/LocalAI) on Railway.

Published as `ghcr.io/bon5co/localai-railway`. Used by the Railway template
`LocalAI | (Just Updated) Self-Hosted OpenAI-Compatible API`.

## What the wrapper adds

LocalAI v4 ships a tiny base image: no inference backend and no model. A stock
container answers every request with
`backend not found: llama-cpp`, and the deployer has to install both by hand
before the API does anything.

1. **A backend and a model baked into the image.** `cpu-llama-cpp` (161 MB) and
   `qwen3-1.7b` (1.2 GB, Apache-2.0) are installed at build time, so the API
   answers on first boot with no gallery pull and no configuration.
2. **The baked assets are seeded onto the volume.** A Railway volume is a bind
   mount, so it hides whatever the image build wrote under its path. Every
   storage path is relocated to `/data/*` and the pristine copies at
   `/opt/localai` are copied across on the first boot only.
3. **It refuses to start without `LOCALAI_API_KEY`.** LocalAI serves inference
   and its web UI to anyone when no key is set, and the URL is public from the
   moment Railway assigns the domain.
4. **It binds the port Railway injected.** LocalAI reads `LOCALAI_ADDRESS`,
   never `PORT`, and Railway's healthcheck dials the injected port.
5. **Threads are sized from the cgroup quota**, not the host's core count, which
   a container always over-reports.
6. **The default model is loaded before the first request** by a warmup call
   issued once the server reports ready.

## Build

```
docker build -t localai-railway:test .
docker run --rm -e LOCALAI_API_KEY=secret -p 8080:8080 -v "$PWD/data":/data localai-railway:test
```

`LOCALAI_DEFAULT_MODEL` is a build argument; change it to bake a different
model from the LocalAI gallery.
