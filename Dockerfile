FROM debian:buster-slim AS debian-base
RUN apt-get update && apt-get -y install wget gnupg unzip curl file

ADD modify-image.sh /usr/local/bin/modify-image
RUN chmod +x /usr/local/bin/modify-image

RUN mkdir -p /raspbian/ /mnt/raspbian/
ADD firstboot.service /raspbian/

VOLUME /raspbian/

ENTRYPOINT ["/usr/local/bin/modify-image"]
CMD ["/raspbian/"]
