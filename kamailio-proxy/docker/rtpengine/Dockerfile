FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        rtpengine \
        iptables && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /var/spool/rtpengine

EXPOSE 22222/udp
EXPOSE 10000-20000/udp

ENTRYPOINT ["rtpengine"]
CMD ["--foreground", "--log-stderr"]
