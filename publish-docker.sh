#!/bin/bash -e

VERSION=$(mvn -q \
    -Dexec.executable="echo" \
    -Dexec.args='${project.version}' \
    --non-recursive \
    org.codehaus.mojo:exec-maven-plugin:1.3.1:exec)

if [[ $VERSION = *"SNAPSHOT"* ]]; then
  echo "Do not publish a snapshot version of rose-build"
  exit 1
fi
docker inspect --type=image rosestack/rose-build:$VERSION  > /dev/null 2>&1
if [[ "$?" -ne 0 ]] ; then
  echo "docker image rosestack/rose-build:$VERSION does not exist - run build_docker.sh first"
  exit 1
fi
docker inspect --type=image rosestack/rose-build:latest  > /dev/null 2>&1
if [[ "$?" -ne 0 ]] ; then
  echo "docker image rosestack/rose-build:latest does not exist - run build_docker.sh first"
  exit 1
fi

docker push rosestack/rose-build:$VERSION
docker push owasp/rose-build:latest
