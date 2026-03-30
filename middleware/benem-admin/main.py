import os
from fastapi import FastAPI
from fastapi.templating import Jinja2Templates
from dotenv import load_dotenv

load_dotenv()

VERSION = "1.0.0"

app = FastAPI(docs_url=None, redoc_url=None)
templates = Jinja2Templates(directory="templates")


@app.get("/admin/health")
def health():
    return {"status": "running", "version": VERSION}
