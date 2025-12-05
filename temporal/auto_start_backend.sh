#!/bin/bash

PORT=1889
SCRIPT_PATH="/home/admin/Desktop/TemporalFiles/temporal_policy.py"
PID_FILE="/home/admin/Desktop/TemporalFiles/temporal-policy.pid"
LOG_FILE="/home/admin/Desktop/TemporalFiles/temporal-policy.log"

# Function to check if backend is running
is_running() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

# Function to start backend
start_backend() {
    echo "[$(date)] Starting backend..." | tee -a "$LOG_FILE"
    
    # Kill any existing process on port
    sudo fuser -k ${PORT}/tcp 2>/dev/null
    sleep 1
    
    # Start backend in background
    sudo nohup python3 "$SCRIPT_PATH" >> "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    
    echo "[$(date)] Backend started with PID $(cat $PID_FILE)" | tee -a "$LOG_FILE"
}

# Function to stop backend
stop_backend() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        echo "[$(date)] Stopping backend PID $PID..." | tee -a "$LOG_FILE"
        sudo kill -9 "$PID" 2>/dev/null
        rm -f "$PID_FILE"
        sudo fuser -k ${PORT}/tcp 2>/dev/null
        echo "[$(date)] Backend stopped" | tee -a "$LOG_FILE"
    else
        echo "No PID file found. Trying to kill by port..."
        sudo fuser -k ${PORT}/tcp 2>/dev/null
        echo "Backend stopped"
    fi
}

case "$1" in
    start)
        if is_running; then
            echo "Backend already running (PID: $(cat $PID_FILE))"
        else
            start_backend
            sleep 2
            if is_running; then
                echo "Backend started successfully!"
            else
                echo "Failed to start backend. Check logs: $LOG_FILE"
            fi
        fi
        ;;
    stop)
        stop_backend
        ;;
    restart)
        stop_backend
        sleep 2
        start_backend
        ;;
    status)
        if is_running; then
            echo "Backend is RUNNING (PID: $(cat $PID_FILE))"
        else
            echo "Backend is NOT running"
        fi
        ;;
    logs)
        if [ -f "$LOG_FILE" ]; then
            tail -f "$LOG_FILE"
        else
            echo "No log file found at $LOG_FILE"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs}"
        exit 1
        ;;
esac
