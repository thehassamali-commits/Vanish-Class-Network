"""Combined entry point. Preserves the supplied Field Sync app and endpoints.
Run from this directory: uvicorn vanish_main:app --host 0.0.0.0 --port 8000
"""
from main import app
from vanish_chat import router
app.include_router(router)
app.title = "Field Sync + Vanish Class Network"
