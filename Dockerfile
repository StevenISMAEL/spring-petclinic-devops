# ── Stage 1: BUILD ──────────────────────────────
FROM eclipse-temurin:21-jdk-alpine AS builder
WORKDIR /app

# Copiar el wrapper de Maven y el pom.xml
COPY .mvn/ .mvn/
COPY mvnw pom.xml ./
RUN chmod +x ./mvnw
RUN ./mvnw dependency:go-offline -q

# Compilar el código
COPY src ./src
RUN ./mvnw package -DskipTests --no-transfer-progress

# Extraer capas de Spring Boot para optimizar cache
RUN java -Djarmode=layertools -jar target/*.jar extract

# ── Stage 2: RUNTIME ────────────────────────────
FROM eclipse-temurin:21-jre-alpine AS runtime

# Usuario no-root (seguridad)
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

WORKDIR /app

# Copiar capas en orden (menos cambiantes primero)
COPY --from=builder /app/dependencies/ ./
COPY --from=builder /app/spring-boot-loader/ ./
COPY --from=builder /app/snapshot-dependencies/ ./
COPY --from=builder /app/application/ ./

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s \
  CMD wget -q --spider http://localhost:8080/actuator/health || exit 1

EXPOSE 8080

# Flags JVM para contenedores
ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"

ENTRYPOINT ["java", "org.springframework.boot.loader.launch.JarLauncher"]