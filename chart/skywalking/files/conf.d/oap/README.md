If you don't want to use the default `application.yml` packed into the Docker image,
put your own `application.yml` under this directory to override the original one.

For now, we support the following files which will override the counterparts in the Docker image.

| File | Override |
| ---- | -------- |
| `application.yml`                 | `/skywalking/config/application.yml`                  |
| `log4j2.xml`                      | `/skywalking/config/log4j2.xml`                       |
| `alarm-settings.yml`              | `/skywalking/config/alarm-settings.yml`               |
| `endpoint-name-grouping.yml`      | `/skywalking/config/endpoint-name-grouping.yml`       |
