FROM ubuntu:22.04

WORKDIR /geo
COPY . /geo

RUN apt-get update && apt-get install jq xmlstarlet

ENTRYPOINT bash install.sh -f
