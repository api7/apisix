ARG REDIS_VERSION

FROM redis:${REDIS_VERSION}-alpine

RUN apk --update --no-cache add supervisor ruby ca-certificates openssl && \
  gem install --no-document redis && \
  REDIS_TRIB_PATH=/usr/local/bin/redis-trib && \
  wget https://raw.githubusercontent.com/antirez/redis/${REDIS_VERSION}/src/redis-trib.rb -O $REDIS_TRIB_PATH && \
  chmod +x $REDIS_TRIB_PATH

COPY start-4.x.sh /start.sh

RUN ["chmod", "+x", "/start.sh"]

VOLUME /data
WORKDIR /

ENV CLUSTER_ANNOUNCE_IP 127.0.0.1

EXPOSE 5000 5001 5002 5003 5004 5005

CMD ["/start.sh"]