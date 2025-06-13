# docker file to monitor pihole dhcp

FROM alpine:latest
LABEL maintainer="jerome@labidurie.fr"

ENV MPH_MONITOR_DELAY=60
ENV MPH_VERBOSE=1

RUN apk add --no-cache tzdata bash dhcping jq curl && mkdir /app

WORKDIR /app
COPY run.sh /app/

ENTRYPOINT ["/app/run.sh"]
