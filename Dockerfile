FROM dart:stable AS build

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN dart pub get

# Activate dart_frog_cli
RUN dart pub global activate dart_frog_cli

COPY . .

# Generate production build
RUN dart pub global run dart_frog_cli:dart_frog build

# Compile the generated server
RUN dart compile exe build/bin/server.dart -o server

FROM debian:bookworm-slim

WORKDIR /app
COPY --from=build /app/server ./server

EXPOSE 8080

CMD ["./server"]