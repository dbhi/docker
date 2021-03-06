#!/bin/sh

set -e

cd "$(dirname $0)"

export DOCKER_BUILDKIT=1

#---

enable_color() {
  ENABLECOLOR='-c '
  ANSI_RED="\033[31m"
  ANSI_GREEN="\033[32m"
  ANSI_YELLOW="\033[33m"
  ANSI_BLUE="\033[34m"
  ANSI_MAGENTA="\033[35m"
  ANSI_GRAY="\033[90m"
  ANSI_CYAN="\033[36;1m"
  ANSI_DARKCYAN="\033[36m"
  ANSI_NOCOLOR="\033[0m"
}

disable_color() { unset ENABLECOLOR ANSI_RED ANSI_GREEN ANSI_YELLOW ANSI_BLUE ANSI_MAGENTA ANSI_CYAN ANSI_DARKCYAN ANSI_NOCOLOR; }

enable_color

print_start() {
  if [ "x$2" != "x" ]; then
    COL="$2"
  elif [ "x$BASE_COL" != "x" ]; then
    COL="$BASE_COL"
  else
    COL="$ANSI_MAGENTA"
  fi
  printf "${COL}${1}$ANSI_NOCOLOR\n"
}

gstart () {
  print_start "$@"
}
gend () {
  :
}

if [ -n "$GITHUB_EVENT_PATH" ]; then
  export CI=true
fi

[ -n "$CI" ] && {
  gstart () {
    printf '::group::'
    print_start "$@"
    SECONDS=0
  }

  gend () {
    duration=$SECONDS
    echo '::endgroup::'
    printf "${ANSI_GRAY}took $(($duration / 60)) min $(($duration % 60)) sec.${ANSI_NOCOLOR}\n"
  }
} || echo "INFO: not in CI"

#---

do_push () {
  gstart "[DOCKER push] $@"
  docker push "$@"
  gend
}

push () {
  docker images
  for i in $imgs; do
    case $i in
      main|base)
        do_push "${DBHI_SLUG}-$DBHI_ARCH"
      ;;
      mambo)
        if [ "x$DBHI_ARCH" = "xamd64" ]; then
          echo "Image <$i> not supported for arch <$DBHI_ARCH>."
          exit 1
        fi
        do_push "${DBHI_SLUG}-${i}-$DBHI_ARCH"
      ;;
      dr|dynamorio)
        do_push "${DBHI_SLUG}-dr-$DBHI_ARCH"
      ;;
      cosim|octave)
        do_push "${DBHI_SLUG}-${i}-$DBHI_ARCH"
      ;;
      grpc|gRPC)
        check_amd64only
        do_push "aptman/dbhi:buster-gRPC-amd64"
      ;;
      spinalhdl)
        check_amd64only
        do_push "${DBHI_SLUG}-spinalhdl-$DBHI_ARCH"
      ;;
      *)
        echo "Unknown image <$i> for host arch <$DBHI_ARCH>"
        exit 1
    esac
  done
}

#---

do_manifests () {
  slug="$1"
  shift
  args=""
  for s in $@; do
    args="$args ${slug}-$s"
  done
  gstart "[DOCKER manifest] $args"
  docker manifest create -a "$slug" $args
  gend
  gstart "[DOCKER push] $slug"
  docker manifest push --purge "$slug"
  gend
}

manifests () {
  do_manifests "$DBHI_SLUG" amd64 arm arm64
  for m in dr cosim octave; do
    do_manifests "${DBHI_SLUG}-$m" amd64 arm arm64
  done
  for m in mambo; do
    do_manifests "${DBHI_SLUG}-$m" arm arm64
  done
  do_manifests "aptman/dbhi:buster-gRPC" amd64
  do_manifests "$DBHI_SLUG"-spinalhdl amd64
# https://github.com/docker/cli/issues/954
}

#---

do_build () {
  gstart "[DOCKER build] $1"
  echo "docker build -t $@"
  docker build -t "$@"
  gend
}

do_build_imgarg () {
  gstart "[DOCKER build] $1"
  echo "docker build -t ${DBHI_SLUG}-$1 --build-arg IMAGE=$2 - < $3"
  docker build -t "${DBHI_SLUG}-$1" --build-arg IMAGE="$2" - < "$3"
  gend
}

check_amd64only () {
  if [ "x$DBHI_ARCH" != "xamd64" ]; then
    echo "Image <$i> not supported for arch <$DBHI_ARCH> yet."
    exit 1
  fi
}

build () {
  for i in $imgs; do
    case $i in
      main|base)
        do_build_imgarg "$DBHI_ARCH" "$IMG" ubuntu-bionic/main.dockerfile
      ;;
      mambo)
        if [ "x$DBHI_ARCH" = "xamd64" ]; then
          echo "Image <$i> not supported for arch <$DBHI_ARCH>."
          exit 1
        fi
        do_build_imgarg "${i}-$DBHI_ARCH" "${DBHI_SLUG}-$DBHI_ARCH" ubuntu-bionic/mambo.dockerfile
      ;;
      dr|dynamorio)
        do_build_imgarg "dr-$DBHI_ARCH" "${DBHI_SLUG}-$DBHI_ARCH" ubuntu-bionic/dynamorio.dockerfile
      ;;
      cosim)
        tgt="arm"
        if [ "x$DBHI_ARCH" = "xamd64" ]; then
          tgt="amd64"
        fi
        do_build "${DBHI_SLUG}-${i}-$DBHI_ARCH" --build-arg IMAGE="${DBHI_SLUG}-$DBHI_ARCH" --target="$tgt" - < ubuntu-bionic/cosim.dockerfile
      ;;
      octave)
        do_build "${DBHI_SLUG}-${i}-$DBHI_ARCH" --build-arg IMAGE="${DBHI_SLUG}-cosim-$DBHI_ARCH" - < ubuntu-bionic/octave.dockerfile
      ;;
      grpc|gRPC)
        check_amd64only
        do_build aptman/dbhi:buster-gRPC-amd64 - < debian-buster/gRPC.dockerfile
      ;;
      spinalhdl)
        check_amd64only
        do_build_imgarg "spinalhdl-amd64" "$IMG" ubuntu-bionic/spinalhdl.dockerfile
      ;;
      *)
        echo "Unknown image <$i> for host arch <$DBHI_ARCH>"
        exit 1
    esac
  done
}

#---

DBHI_SLUG="aptman/dbhi:bionic"
echo "DBHI_SLUG: $DBHI_SLUG"

if [ -z "$TGT_ARCHS" ]; then
  TGT_ARCHS="$(uname -m)"
fi

subcmd="$1"
shift

dimgs="ALL"
if [ $# -ne 0 ] && [ "x$@" != "xALL" ]; then
  dimgs="$@"
fi

for DBHI_ARCH in $TGT_ARCHS; do
  case $DBHI_ARCH in
    aarch64|arm64)
      DBHI_ARCH="arm64"
      IMG="arm64v8/ubuntu:bionic"
    ;;
    aarch32|armv7l|arm)
      DBHI_ARCH="arm"
      IMG="arm32v7/ubuntu:bionic"
    ;;
    x86_64|amd64)
      DBHI_ARCH="amd64"
      IMG="ubuntu:bionic"
    ;;
    *)
      echo "Unknown arch $DBHI_ARCH..."
      exit 1
    ;;
  esac
  imgs="$dimgs"
  if [ "x$imgs" = "xALL" ]; then
    case $DBHI_ARCH in
      amd64)
        imgs="main dr gRPC cosim octave spinal"
      ;;
      arm64|arm)
        imgs="main mambo dr cosim octave"
      ;;
    esac
  fi
  case "$subcmd" in
    "-b")
      build "$imgs"
    ;;
    "-p")
      push "$imgs"
    ;;
    "-m")
      manifests
    ;;
    *)
      echo "Unknown arg <$1>"
      exit 1
    ;;
  esac
done
