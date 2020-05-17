FROM alpine:3.11

RUN apk add --no-cache file gnupg curl wget unzip

ADD modify-image.sh /usr/local/bin/modify-image
RUN chmod +x /usr/local/bin/modify-image

RUN mkdir -p /raspbian/ /mnt/raspbian/
ADD firstboot.service /raspbian/

VOLUME /raspbian/

ENTRYPOINT ["/usr/local/bin/modify-image"]
CMD ["/raspbian/"]
