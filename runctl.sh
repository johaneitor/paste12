#!/usr/bin/env bash
set -euo pipefail
PORT="${PORT:-8000}"
PIDFILE=".server.pid"
LOGFILE="server.log"

start() {
  if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "Ya está corriendo (PID $(cat $PIDFILE)). Usa '$0 status' o '$0 restart'."
    exit 0
  fi
  echo "[start] PORT=$PORT → lanzando ./serve.sh en background..."
  nohup ./serve.sh >"$LOGFILE" 2>&1 &
  echo $! > "$PIDFILE"
  # Espera corta y chequeo
  sleep 1
  if curl -sI "http://127.0.0.1:$PORT/" | head -n1 | grep -q "HTTP/"; then
    echo "✔ Escuchando en :$PORT (PID $(cat $PIDFILE))"
  else
    echo "⚠ No responde todavía. Mirá logs con: $0 logs"
  fi
}

stop() {
  if [ -f "$PIDFILE" ]; then
    PID="$(cat "$PIDFILE")"
    echo "[stop] matando PID $PID ..."
    kill "$PID" 2>/dev/null || true
    sleep 1
    kill -9 "$PID" 2>/dev/null || true
    rm -f "$PIDFILE"
  fi
  # por si quedó algo en el puerto:
  command -v fuser >/dev/null 2>&1 && fuser -k "$PORT"/tcp 2>/dev/null || true
  command -v lsof  >/dev/null 2>&1 && lsof -tiTCP:"$PORT" -sTCP:LISTEN | xargs -r kill 2>/dev/null || true
  echo "✔ Detenido"
}

status() {
  if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "UP  (PID $(cat $PIDFILE), puerto $PORT)"
  else
    echo "DOWN (puerto $PORT)"
  fi
  curl -sI "http://127.0.0.1:$PORT/health" | head -n1 || true
}

restart() { stop; start; }
logs() { tail -n 100 -f "$LOGFILE"; }

case "${1:-}" in
  start|stop|status|restart|logs) "$1" ;;
  *) echo "Uso: $0 {start|stop|status|restart|logs}"; exit 2;;
esac
