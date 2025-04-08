FROM eclipse-temurin:17-jdk-alpine

WORKDIR /app

COPY target/healthcare-me-service-1.0.0.jar app.jar

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "app.jar"]
