"""Disposable sandbox service for trying the crawl/walk patterns end to end
before pointing either one at a real service. Not meant to be production code.

FAULT_INJECTION=true makes `/` slow and occasionally fail, which is enough for
Dynatrace's own problem detection to open a real Davis problem - the thing the
cause/fix deployment events in ../crawl-argocd-notifications and
../walk-cicd-events-api are meant to attach to.
"""
import os
import random
import time

from flask import Flask

app = Flask(__name__)


def fault_injection_enabled():
    return os.environ.get("FAULT_INJECTION", "false").lower() == "true"


@app.get("/healthz")
def healthz():
    return {"status": "ok"}, 200


@app.get("/")
def index():
    if fault_injection_enabled():
        time.sleep(3)
        if random.random() < 0.5:
            return {"status": "error"}, 500
    return {"status": "ok"}, 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
