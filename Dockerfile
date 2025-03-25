FROM openjdk:11-jdk
COPY target/healthcare-me-service-1.0.0.jar app.jar
ENTRYPOINT ["java", "-jar", "/app.jar"]

