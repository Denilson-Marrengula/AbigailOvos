FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /source
COPY pom.xml .
COPY src ./src
RUN mvn -B -DskipTests package

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /source/target/backend-0.0.1-SNAPSHOT.jar /app/backend.jar
USER 10001:10001
# Render forwards to $PORT (default 10000); staging overrides SERVER_PORT=8443.
ENV PORT=10000
EXPOSE 10000 8443
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=65.0", "-jar", "/app/backend.jar"]
