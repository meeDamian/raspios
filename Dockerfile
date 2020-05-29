FROM debian:buster-slim

RUN apt-get update && \
    apt-get -y install \
        curl \
        file \
        gnupg \
        unzip \
        wget \
        zip

ADD modify-image.sh /usr/local/bin/modify-image
RUN chmod +x        /usr/local/bin/modify-image

RUN mkdir -p /mnt/raspios/                     /data/
ADD firstboot.service firstboot-script.service /data/

VOLUME  /raspios/
WORKDIR /raspios/

ENTRYPOINT ["/usr/local/bin/modify-image"]
CMD ["create", "/raspios/"]
