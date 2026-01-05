# syncmind

This folder contains SyncMind-specific automation for building and publishing Dify Docker images.

## Alibaba Cloud ACR (latest-only)

Target registry/namespace:

- Registry: `crpi-2e30x3ttfmqmx83q.cn-chengdu.personal.cr.aliyuncs.com`
- Namespace: `dify-vision`

Published images (x86 only):

- `crpi-2e30x3ttfmqmx83q.cn-chengdu.personal.cr.aliyuncs.com/dify-vision/dify-api:latest`
- `crpi-2e30x3ttfmqmx83q.cn-chengdu.personal.cr.aliyuncs.com/dify-vision/dify-web:latest`

Mirrored upstream images used by `docker/docker-compose.yaml` (so ECS does not need `docker.io`) are pushed under:

- `crpi-2e30x3ttfmqmx83q.cn-chengdu.personal.cr.aliyuncs.com/dify-vision/<flattened_repo>:<original_tag>`

Note: Alibaba ACR repositories under a namespace cannot contain extra `/`. The workflow flattens upstream image names to the last path segment.

Example:

- `redis:6-alpine` -> `crpi-2e30x3ttfmqmx83q.cn-chengdu.personal.cr.aliyuncs.com/dify-vision/redis:6-alpine`
- `ubuntu/squid:latest` -> `crpi-2e30x3ttfmqmx83q.cn-chengdu.personal.cr.aliyuncs.com/dify-vision/ubuntu/squid:latest`
- `certbot/certbot` -> `crpi-2e30x3ttfmqmx83q.cn-chengdu.personal.cr.aliyuncs.com/dify-vision/certbot:latest`

### GitHub Actions

Workflow: `.github/workflows/syncmind-push-acr.yml`

Mirror workflow (recommended for dependency images): `.github/workflows/syncmind-mirror-acr.yml`

Required GitHub secrets:

- `ALIYUN_ACR_USERNAME`
- `ALIYUN_ACR_PASSWORD`

Trigger:

- Manual only (`workflow_dispatch`).

## Deploy on Alibaba ECS (ACR-only pulls)

1) Mirror dependency images (run GitHub workflow: `.github/workflows/syncmind-mirror-acr.yml`).

2) Build/push `dify-api:latest` and `dify-web:latest` (run GitHub workflow: `.github/workflows/syncmind-push-acr.yml`).

3) On the ECS instance, deploy using the base compose plus the ACR override:

```sh
docker login crpi-2e30x3ttfmqmx83q.cn-chengdu.personal.cr.aliyuncs.com
docker compose \
	-f docker/docker-compose.yaml \
	-f syncmind/docker-compose.acr.override.yaml \
	up -d
```

The override file `syncmind/docker-compose.acr.override.yaml` rewrites all `image:` references from `docker/docker-compose.yaml` to ACR, using the flattened repo naming required by Alibaba ACR.

## HTTPS / Certbot

See `syncmind/CERTBOT_RENEWAL.md` for how HTTPS is set up (nginx + certbot profile) and how to renew the certificate.

### Local push (optional)

1) Login:

```sh
docker login crpi-2e30x3ttfmqmx83q.cn-chengdu.personal.cr.aliyuncs.com
```

2) Build & push:

```sh
./syncmind/scripts/push-acr-latest.sh
```

3) Mirror all compose dependency images to ACR:

```sh
./syncmind/scripts/mirror-compose-images.sh
```

4) Mirror only selected images (reduce runner disk usage / retries):

```sh
./syncmind/scripts/mirror-compose-images.sh --image redis:6-alpine --image ubuntu/squid:latest
```

### Notes

- The mirror workflow defaults to `skopeo` (streaming copy) to reduce disk usage on GitHub runners.
- You can also pass `images` to the mirror workflow input (comma or newline separated).
```
