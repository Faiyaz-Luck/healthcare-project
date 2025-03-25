FROM openjdk:11-jdk
COPY target/healthcare-0.0.1-SNAPSHOT.jar app.jar
ENTRYPOINT ["java", "-jar", "/app.jar"]
