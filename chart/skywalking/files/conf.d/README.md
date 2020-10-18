If you don't want to use the default configuration files packed into the Docker image,
put your own configuration files under this directory in the corresponding component subdirectory,
`oap`, `ui`, etc.

For now, we support the following files which will override the counterparts in the Docker image.

| File | Override |
| ---- | -------- |
| `oap/application.yml` | The `application.yml` in the OAP Docker image |
