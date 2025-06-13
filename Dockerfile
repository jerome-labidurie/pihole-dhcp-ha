# docker file to monitor pihole dhcp

FROM alpine:latest
LABEL org.opencontainers.image.source=https://github.com/jerome-labidurie/pihole-dhcp-ha
LABEL org.opencontainers.image.description="kind of High Availability for Pi-hole DHCP/DNS services"
LABEL org.opencontainers.image.licenses=GPL-3.0-only


ENV MPH_MONITOR_DELAY=60
ENV MPH_VERBOSE=1

RUN apk add --no-cache tzdata bash dhcping jq curl && mkdir /app

WORKDIR /app
COPY run.sh /app/

ENTRYPOINT ["/app/run.sh"]
