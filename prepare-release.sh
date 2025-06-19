#!/bin/bash -e

git checkout main
git pull --rebase

SNAPSHOT=$(mvn help:evaluate -Dexpression=project.version -q -DforceStdout)
RELEASE=${SNAPSHOT/-SNAPSHOT/}

git checkout -b "release-$RELEASE"

#  mvn release:prepare -DinteractiveMode=false -DnoBackup=true -DreleaseVersion=$RELEASE_VERSION -Dtag=v$RELEASE_VERSION -DdevelopmentVersion=$NEXT_VERSION
mvn -ntp -B release:prepare release:clean

git push origin "release-$RELEASE"

git checkout main

git branch -D "release-$RELEASE"
