FROM golang:1.25 AS builder

ENV GOTOOLCHAIN=auto

ARG project="cue"
ARG fuzzTarget="parser-fuzz"
ARG fuzzTargetPath="cuelang.org/go/cue/parser"
ARG fuzzFunc="FuzzParseFile"

ADD . /src/${project}
WORKDIR /src/${project}
RUN go test -c -fuzz=${fuzzFunc} -o /${fuzzTarget}.libfuzzer ${fuzzTargetPath}

FROM ubuntu:22.04
COPY --from=builder /parser-fuzz.libfuzzer /
