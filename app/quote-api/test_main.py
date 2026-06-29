import pytest
from fastapi.testclient import TestClient

from main import app


@pytest.fixture
def client():
    with TestClient(app) as c:
        yield c


def test_healthz(client):
    assert client.get("/healthz").json() == {"status": "ok"}


def test_readyz(client):
    assert client.get("/readyz").status_code == 200
    assert client.get("/readyz").json()["status"] == "ready"


def test_metrics(client):
    r = client.get("/metrics")
    assert r.status_code == 200
    assert "quote_requests_total" in r.text


def test_quote(client):
    r = client.get("/api/quote")
    assert r.status_code == 200
    body = r.json()
    assert "text" in body and "author" in body
