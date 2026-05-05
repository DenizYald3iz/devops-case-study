#!/bin/sh
PORT="${STREAMLIT_SERVER_PORT:-8501}"
echo ""
echo "  App running at: http://localhost:${PORT}"
echo ""
exec streamlit run main.py \
  --server.port="${PORT}" \
  --server.address=0.0.0.0 \
  --server.headless=true \
  --browser.gatherUsageStats=false
