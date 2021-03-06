ARG IMAGE="ubuntu:bionic"

FROM $IMAGE

RUN apt-get update -qq \
 && DEBIAN_FRONTEND=noninteractive apt-get -y install --no-install-recommends \
    octave \
 && apt-get autoclean && apt-get clean && apt-get -y autoremove \
 && update-ca-certificates
