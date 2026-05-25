$ErrorActionPreference = "Stop"

$env:SPRING_DATASOURCE_URL = "jdbc:mysql://localhost:3307/fitloop?useUnicode=true&characterEncoding=utf8&serverTimezone=Asia/Shanghai&allowPublicKeyRetrieval=true&useSSL=false"
$env:SPRING_DATASOURCE_USERNAME = "fitloop"
$env:SPRING_DATASOURCE_PASSWORD = "fitloop"
$env:SPRING_DATA_REDIS_HOST = "localhost"
$env:SPRING_DATA_REDIS_PORT = "6379"
$env:SPRING_REDIS_HOST = "localhost"
$env:SPRING_REDIS_PORT = "6379"
$env:FITLOOP_JWT_SECRET = "local-dev-secret-local-dev-secret"
$env:FITLOOP_ADMIN_KEY = "local-admin-key"

mvn spring-boot:run
