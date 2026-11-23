# syntax=docker/dockerfile:1
# Construir desde la raiz del repositorio: docker build -f api-gateway/Dockerfile .
# Etapa 1: compilacion del modulo y sus dependencias dentro del reactor Maven
FROM maven:3.9-eclipse-temurin-21-alpine AS builder
WORKDIR /workspace
COPY pom.xml .
COPY common-persistence/pom.xml common-persistence/
COPY eureka-server/pom.xml eureka-server/
COPY api-gateway/pom.xml api-gateway/
COPY ms-cuentas/pom.xml ms-cuentas/
COPY ms-transacciones/pom.xml ms-transacciones/
COPY api-gateway/src api-gateway/src
RUN --mount=type=cache,target=/root/.m2 mvn -B -q -pl api-gateway -am clean package -DskipTests

# Etapa 2: imagen minima de ejecucion (curl para el healthcheck de Compose)
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
RUN apk add --no-cache curl
COPY --from=builder /workspace/api-gateway/target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
