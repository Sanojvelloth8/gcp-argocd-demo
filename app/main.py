import os

import httpx
from fastapi import FastAPI, HTTPException

app = FastAPI()

OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "http://ollama.llm-inference.svc.cluster.local:11434")
MODEL = os.environ.get("OLLAMA_MODEL", "llama3.2:1b")


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.get("/ask")
def ask(q: str):
    if not q:
        raise HTTPException(status_code=400, detail="missing query param 'q'")

    try:
        resp = httpx.post(
            f"{OLLAMA_HOST}/api/generate",
            # num_predict caps response length — CPU inference is slow enough
            # that an open-ended question can otherwise take minutes.
            json={"model": MODEL, "prompt": q, "stream": False, "options": {"num_predict": 200}},
            timeout=120.0,
        )
        resp.raise_for_status()
    except httpx.HTTPError as e:
        raise HTTPException(status_code=502, detail=str(e))

    answer = resp.json()["response"]
    return {"question": q, "answer": answer, "model": MODEL}
