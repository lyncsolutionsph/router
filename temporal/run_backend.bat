@echo off
REM Run the FastAPI backend stub on port 5000
python -m uvicorn backend_stub:app --host 0.0.0.0 --port 5000 --reload
PAUSE
