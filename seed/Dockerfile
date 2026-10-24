FROM golang:1.25-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/seed .

FROM alpine:3.20
COPY --from=build /out/seed /usr/local/bin/seed
ENTRYPOINT ["/usr/local/bin/seed"]
