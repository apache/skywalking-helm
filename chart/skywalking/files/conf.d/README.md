If you don't want to use the default configuration files packed into the Docker image,
put your own configuration files under this directory in the corresponding component subdirectory,
`oap`, `ui`, etc.

For now, we support the following files which will override the counterparts in the Docker image.

| File | Override |
| ---- | -------- |
| `oap/application.yml`                 | `/skywalking/config/application.yml`                  |
| `oap/log4j2.xml`                      | `/skywalking/config/log4j2.xml`                       |
| `oap/alarm-settings.yml`              | `/skywalking/config/alarm-settings.yml`               |
| `oap/endpoint-name-grouping.yml`      | `/skywalking/config/endpoint-name-grouping.yml`       |
