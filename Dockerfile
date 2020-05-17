FROM debian:buster-slim

RUN apt-get update && \
    apt-get -y install curl file gnupg unzip wget zip

ADD modify-image.sh /usr/local/bin/modify-image
RUN chmod +x /usr/local/bin/modify-image

RUN mkdir -p /data/ /mnt/raspbian/
ADD firstboot.service /data/

VOLUME /raspbian/
WORKDIR /raspbian/

ENTRYPOINT ["/usr/local/bin/modify-image"]
CMD ["magic", "/raspbian/"]
