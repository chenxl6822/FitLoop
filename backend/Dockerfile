ARG MAVEN_IMAGE=maven:3.9.9-eclipse-temurin-17
ARG JRE_IMAGE=eclipse-temurin:17-jre

FROM ${MAVEN_IMAGE} AS build
WORKDIR /workspace
COPY pom.xml .
COPY .mvn ./.mvn
COPY src ./src
RUN mvn -q -DskipTests package

FROM ${JRE_IMAGE}
WORKDIR /app
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /workspace/target/fitloop-backend-*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
