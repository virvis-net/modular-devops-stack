# Minimal Go web app example
FROM golang:1.22-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
COPY src/ .
RUN go build -o server .

FROM alpine:3.19
WORKDIR /app
COPY --from=builder /app/server .
EXPOSE 8080
EXPOSE 9090
CMD ["./server"]
