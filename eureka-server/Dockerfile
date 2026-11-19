# syntax=docker/dockerfile:1
# Construir desde la raiz del repositorio: docker build -f eureka-server/Dockerfile .
# Etapa 1: compilacion del modulo y sus dependencias dentro del reactor Maven
FROM maven:3.9-eclipse-temurin-21-alpine AS builder
WORKDIR /workspace
COPY pom.xml .
COPY common-persistence/pom.xml common-persistence/
COPY eureka-server/pom.xml eureka-server/
COPY api-gateway/pom.xml api-gateway/
COPY ms-cuentas/pom.xml ms-cuentas/
COPY ms-transacciones/pom.xml ms-transacciones/
COPY eureka-server/src eureka-server/src
RUN --mount=type=cache,target=/root/.m2 mvn -B -q -pl eureka-server -am clean package -DskipTests

# Etapa 2: imagen minima de ejecucion (curl para el healthcheck de Compose)
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
RUN apk add --no-cache curl
COPY --from=builder /workspace/eureka-server/target/*.jar app.jar
EXPOSE 8761
ENTRYPOINT ["java", "-jar", "app.jar"]
