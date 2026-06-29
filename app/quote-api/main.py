import os
import random
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, Response
from fastapi.responses import JSONResponse
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

APP_VERSION = os.getenv("APP_VERSION", "dev")
CPU_BURN_SECONDS = float(os.getenv("CPU_BURN_SECONDS", "0.1"))

QUOTES = [
    {"text": "The best way out is always through.", "author": "Robert Frost"},
    {"text": "What we fear of doing most is usually what we most need to do.", "author": "Tim Ferriss"},
    {"text": "Done is better than perfect.", "author": "Sheryl Sandberg"},
    {"text": "Discipline equals freedom.", "author": "Jocko Willink"},
    {"text": "Make it work, make it right, make it fast.", "author": "Kent Beck"},
    {"text": "Simplicity is the soul of efficiency.", "author": "Austin Freeman"},
    {"text": "Hard things are hard.", "author": "Anonymous"},
]

_ready = False


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _ready
    _ready = True
    yield


app = FastAPI(title="quote-api", version=APP_VERSION, lifespan=lifespan)

REQUESTS = Counter("quote_requests_total", "Total /api/quote requests served")
LATENCY = Histogram(
    "quote_request_duration_seconds",
    "Latency of /api/quote in seconds",
    buckets=(0.05, 0.1, 0.15, 0.2, 0.3, 0.5, 1.0),
)


def _burn_cpu(seconds: float) -> int:
    deadline = time.perf_counter() + seconds
    x = 0
    while time.perf_counter() < deadline:
        x = (x * 1_103_515_245 + 12_345) & 0x7FFFFFFF
    return x


@app.get("/healthz")
def healthz() -> dict:
    return {"status": "ok"}


@app.get("/readyz")
def readyz() -> Response:
    if not _ready:
        return JSONResponse({"status": "starting"}, status_code=503)
    return JSONResponse({"status": "ready"})


@app.get("/metrics")
def metrics() -> Response:
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/api/quote")
def quote() -> dict:
    with LATENCY.time():
        _burn_cpu(CPU_BURN_SECONDS)
        REQUESTS.inc()
        return random.choice(QUOTES)
