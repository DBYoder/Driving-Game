# Highway 1 on the web (see app.py). Railway builds this from the `web` branch, which CI
# fills with this folder and the game's web build in public/.
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
COPY public ./public
# gzip copies for browsers that take them (all of them): the game's 56 MB becomes 20.
RUN find public -type f \( -name '*.wasm' -o -name '*.pck' -o -name '*.js' -o -name '*.html' \) \
    -exec gzip -9 -k -f {} \;
ENV GAME_DIR=/app/public
# (exec: uvicorn gets Railway's stop signal itself and shuts down cleanly)
CMD ["sh", "-c", "exec uvicorn app:app --host 0.0.0.0 --port ${PORT:-8080} --proxy-headers --forwarded-allow-ips='*'"]
