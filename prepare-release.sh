#!/bin/bash -e

git checkout main
git pull --rebase

SNAPSHOT=$(mvn help:evaluate -Dexpression=project.version -q -DforceStdout)
RELEASE=${SNAPSHOT/-SNAPSHOT/}

git checkout -b "release-$RELEASE"

mvn -ntp -B release:prepare
mvn -ntp -B release:clean

git push origin "release-$RELEASE"

git checkout main

git branch -D "release-$RELEASE"
