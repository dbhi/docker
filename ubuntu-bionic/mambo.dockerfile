ARG IMAGE="ubuntu:bionic"

FROM $IMAGE

RUN apt update -qq \
 && DEBIAN_FRONTEND=noninteractive apt -y install --no-install-recommends \
   libelf-dev \
   ruby \
 && apt autoclean && apt clean && apt -y autoremove \
 && mkdir -p /opt/mambo \
 && curl -fsSL https://codeload.github.com/beehive-lab/mambo/tar.gz/master | tar xzf - -C /opt/mambo --strip-components=1 \
 && mkdir -p /opt/mambo/pie \
 && curl -fsSL https://codeload.github.com/beehive-lab/pie/tar.gz/master | tar xzf - -C /opt/mambo/pie --strip-components=1

ENV DBHI_MAMBO /opt/mambo/
