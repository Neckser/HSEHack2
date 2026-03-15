# Меняем версию с 1.21 на 1.25
FROM golang:1.25-alpine AS builder

# Устанавливаем системные зависимости для скриншотов
RUN apk add --no-cache gcc musl-dev linux-headers

WORKDIR /app

# Копируем модули
COPY go.mod go.sum ./
RUN go mod download

# Копируем исходники
COPY . .

# Собираем бинарник
RUN go build -o screener main.go

# Финальный образ
FROM alpine:latest

# Библиотеки для скриншотов
RUN apk add --no-cache \
    libx11 libxrandr libxinerama libxcursor libxi \
    mesa-gl xdotool ca-certificates

WORKDIR /app

# Копируем бинарник
COPY --from=builder /app/screener .

# Создаем папку для скриншотов
RUN mkdir -p /app/screenshots

# Запускаем
CMD ["./screener"]