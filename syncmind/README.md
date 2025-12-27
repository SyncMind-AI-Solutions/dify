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

- `crpi-2e30x3ttfmqmx83q.cn-chengdu.personal.cr.aliyuncs.com/dify-vision/<original_repo>:<original_tag>`

Example:

- `redis:6-alpine` -> `crpi-2e30x3ttfmqmx83q.cn-chengdu.personal.cr.aliyuncs.com/dify-vision/redis:6-alpine`
- `ubuntu/squid:latest` -> `crpi-2e30x3ttfmqmx83q.cn-chengdu.personal.cr.aliyuncs.com/dify-vision/ubuntu/squid:latest`

### GitHub Actions

Workflow: `.github/workflows/syncmind-push-acr.yml`

Required GitHub secrets:

- `ALIYUN_ACR_USERNAME`
- `ALIYUN_ACR_PASSWORD`

Trigger:

- Manual only (`workflow_dispatch`).

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
