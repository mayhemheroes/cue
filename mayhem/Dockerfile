FROM fuzzers/go-fuzz:1.2.0 as builder

ARG project='cue'
ARG fuzzTargetPath='cue/parser'
ARG fuzzTarget='parser-fuzz'

ADD . ${project}
WORKDIR ${project}
RUN GO_ENABLED=0 go-fuzz-build -libfuzzer -o /${fuzzTarget}-fuzz.a ./${fuzzTargetPath}
RUN clang -fsanitize=fuzzer /${fuzzTarget}.a -o /${fuzzTarget}.libfuzzer

FROM ubuntu:20.04
COPY --from=builder /${fuzzTarget}.libfuzzer /
