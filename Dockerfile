# syntax=docker/dockerfile:1
FROM python:3.8-slim-buster
RUN apt update && apt install -y libpq-dev
WORKDIR /app
COPY requirements.txt requirements.txt
RUN pip3 install -r requirements.txt
COPY runner.py runner.py
COPY docker-entrypoint.sh /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]
