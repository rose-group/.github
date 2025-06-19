FROM maven:3.9.2-eclipse-temurin-8-alpine AS builder

COPY ./src src/
COPY ./pom.xml pom.xml

RUN mvn clean package -DskipTests

FROM eclipse-temurin:8-jre-alpine
COPY --from=builder target/*.jar app.jar
EXPOSE 8080

CMD ["java","-jar","app.jar"]