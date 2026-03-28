FROM dart:stable AS build

WORKDIR /app

# Copy pubspec files and get dependencies
COPY pubspec.yaml pubspec.lock ./
RUN dart pub get

# Copy the rest of the source
COPY . .

# Compile to a native executable
RUN dart compile exe bin/server.dart -o bin/server

# Use a minimal runtime image
FROM debian:bookworm-slim

WORKDIR /app
COPY --from=build /app/bin/server ./server

# Railway injects PORT env var
EXPOSE 8080

CMD ["./server"]