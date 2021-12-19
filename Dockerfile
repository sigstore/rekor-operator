# Build the manager binary
FROM golang:1.17.5 as builder

WORKDIR /workspace

# Run this with docker build --build_arg $(go env GOPROXY) to override the goproxy
ARG goproxy=https://proxy.golang.org
ENV GOPROXY=$goproxy

# Copy the Go Modules manifests
COPY go.mod go.mod
COPY go.sum go.sum
# cache deps before building and copying source so that we don't need to re-download as much
# and so that source changes don't invalidate our downloaded layer
RUN go mod download

# Copy the sources
COPY ./ ./

# Build
ARG LDFLAGS
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
  go build -a -trimpath -ldflags "${LDFLAGS} -extldflags '-static'" \
  -o manager .

# Copy the controller-manager into a thin image
FROM gcr.io/distroless/static:latest
WORKDIR /
COPY --from=builder /workspace/manager .
USER nobody
ENTRYPOINT ["/manager"]
