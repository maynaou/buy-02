ARG DOCKERHUB_PROXY=docker.io
FROM ${DOCKERHUB_PROXY}/library/eclipse-temurin:17-jre

WORKDIR /app

COPY target/*.jar app.jar


ENTRYPOINT ["java", "-jar", "app.jar"]