#!/bin/bash

gitlab_home_volume="gitlab-home"
gitlab_runner_config_volume="gitlab-runner-config"

# Create external volumes with folders
# So to be sure our data does not dissapear when we delete/update the container/image
if ! docker volume inspect ${gitlab_home_volume} > /dev/null 2>&1
then
  docker volume create ${gitlab_home_volume}
  docker run -it --rm -v ${gitlab_home_volume}:/data debian:stable-slim mkdir /data/config /data/log /data/data
fi

if ! docker volume inspect ${gitlab_runner_config_volume} > /dev/null 2>&1
then
  docker volume create ${gitlab_runner_config_volume}
  docker run -it --rm -v ${gitlab_runner_config_volume}:/data debian:stable-slim mkdir /data/runner-0
fi

read -p "Enter hostname (gitlab.example.com): " hostname

export HOSTNAME="$hostname"

# Create networks and containers and start the services
# docker compose create --no-recreate --quiet-pull
docker compose up --detach --quiet-pull --quiet-build

# Get gitlab container ip and add it to the /etc/hosts file
if ! grep ${hostname} /etc/hosts
then
  networkname="${hostname//./}_default"
  ip=$(docker inspect -f "{{.NetworkSettings.Networks.${networkname}.IPAddress}}" gitlab)
  echo $ip $hostname | sudo tee -a /etc/hosts
fi

# Reset root password
echo "Next you'll need to reset the root password to be able to use your gitlab server."
echo "Please be patient, it takes a second to load. When asked enter username 'root' and follow the instructions."
# docker container exec -it gitlab  gitlab-rake "gitlab:password:reset"

# Create a personal access token for use with api.
echo "Please create and provide a personal access token to finish setting up the runner"
echo "https://${hostname}/-/user_settings/personal_access_tokens"

read -p "Access token: " access_token

# Setup SSL certificate
openssl s_client -showcerts -connect ${hostname}:443 </dev/null 2>/dev/null | openssl x509 -outform PEM > ${hostname}.crt

# Create the runner
runner_info=$(curl --request POST \
  --cacert "${hostname}.crt" \
  --header "PRIVATE-TOKEN: ${access_token}" \
  --data "runner_type=instance_type" \
  --url "https://${hostname}/api/v4/user/runners")

# {"id":1,"token":"xx","token_expires_at":null}

obtained_at=$(date +%Y-%m-%dT%H:%M:%SZ)
id=$(echo $runner_info | jq -r ".id")
token=$(echo $runner_info | jq -r ".token")
network_mode="${hostname//./}_backend"

# Create config.toml
IFS='' read -r -d '' config_toml <<EOF
concurrent = 1
check_interval = 0
shutdown_timeout = 0

[session_server]
  session_timeout = 1800

[[runners]]
  name = \"gitlab-runner-0\"
  url = \"https://${hostname}\"
  id = ${id}
  token = \"${token}\"
  token_obtained_at = ${obtained_at}
  token_expires_at = 0001-01-01T00:00:00Z
  executor = \"docker\"
  [runners.cache]
    MaxUploadedArchiveSize = 0
    [runners.cache.s3]
    [runners.cache.gcs]
    [runners.cache.azure]
  [runners.docker]
    tls_verify = false
    image = \"debian:stable-slim\"
    pull_policy = \"if-not-present\" 
    privileged = false
    disable_entrypoint_overwrite = false
    oom_kill_disable = false
    disable_cache = false
    volumes = [\"/cache\"]
    shm_size = 0
    network_mtu = 0
    network_mode = \"${network_mode}\"
EOF

docker container exec gitlab-runner-0 /bin/bash -c "echo \"${config_toml}\" > /etc/gitlab-runner/config.toml"
