FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 SIGNAL_HOST=0.0.0.0 SIGNAL_PORT=8765
WORKDIR /app
COPY server/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt
COPY server/signaling_server.py ./signaling_server.py
COPY server/stream_relay.py ./stream_relay.py
EXPOSE 8765
USER 10001:10001
CMD ["python", "signaling_server.py"]
