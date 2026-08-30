#!/usr/bin/env bash
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Query Horizon UI's BFF the way an operator does: log in, then call an API with
# the session cookie. Every request in the e2e goes through here, so the whole
# suite exercises horizon -> oap -> storage rather than talking to OAP directly.
#
#   horizon.sh <base-url> get  <api-path>
#   horizon.sh <base-url> post <api-path> <json-body>
#
# Credentials come from HORIZON_USERNAME / HORIZON_PASSWORD and default to the
# admin/admin pair that test/e2e/values.yaml seeds. There is no built-in login:
# Horizon ships `auth.local.users` empty, so without that values file every call
# here fails at the login step -- which is the intended signal, not a flake.

set -eo pipefail

BASE_URL=$1
VERB=$2
API_PATH=$3
BODY=${4:-}

USERNAME=${HORIZON_USERNAME:-admin}
PASSWORD=${HORIZON_PASSWORD:-admin}

JAR=$(mktemp)
trap 'rm -f "$JAR"' EXIT

curl -sS --fail-with-body -c "$JAR" -X POST "${BASE_URL}/api/auth/login" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"${USERNAME}\",\"password\":\"${PASSWORD}\"}" >/dev/null

grep -q 'horizon_sid' "$JAR" || { echo "login did not set a session cookie" >&2; exit 1; }

if [ "$VERB" = "post" ]; then
  curl -sS --fail-with-body -b "$JAR" -X POST "${BASE_URL}${API_PATH}" \
    -H 'Content-Type: application/json' -d "$BODY"
else
  curl -sS --fail-with-body -b "$JAR" "${BASE_URL}${API_PATH}"
fi
