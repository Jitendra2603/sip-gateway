FROM ghcr.io/kamailio/kamailio-ci:5.8

COPY kamailio.cfg /etc/kamailio/kamailio.cfg.template
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 5060/udp
EXPOSE 5060/tcp
EXPOSE 5061/tcp

ENTRYPOINT ["/entrypoint.sh"]
