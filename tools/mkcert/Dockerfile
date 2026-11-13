FROM golang:1.27.1-alpine3.24 AS build

RUN CGO_ENABLED=0 go install filippo.io/mkcert@v1.4.4

FROM scratch

COPY --from=build /go/bin/mkcert /mkcert

ENTRYPOINT ["/mkcert"]
