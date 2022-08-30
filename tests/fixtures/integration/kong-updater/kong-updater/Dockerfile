FROM alpine:latest
ENV KONG_ADMIN_URL="http://kong-control-plane:8001"
ENV UPDATE_RATE="30"
ENV UPDATE_TYPE="service_retries"
ENV KONG_ADMIN_TOKEN="password"
ENV PREFIX="perf"
RUN apk add curl
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
