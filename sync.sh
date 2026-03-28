#!/bin/bash
set -eux

# 检查参数数量是否正确
if [ "$#" -ne 3 ]; then
    echo "错误：脚本需要3个参数 images_file、docker_registry和docker_namespace"
    echo "用法: $0 <images_file> <docker_registry> <docker_namespace>"
    exit 1
fi

IMAGES_FILE=$1
TARGET_REGISTRY=$2
TARGET_NAMESPACE=$3

# 第二个目标仓库：Docker Hub（请修改为你的用户名和仓库名）
DOCKERHUB_USER="maomao1714"
DOCKERHUB_REPO="mao_hub"          # 你的 Docker Hub 仓库名

# 检查文件是否存在
if [ ! -f "$IMAGES_FILE" ]; then
    echo "错误：文件 $IMAGES_FILE 不存在"
    exit 1
fi

failed_count=0
failed_images=""
while IFS= read -r image; do
    # 拉取镜像（指定 arm64 平台）
    set +e
    docker pull --platform linux/arm64 "$image"
    pull_status=$?
    if [ $pull_status -ne 0 ]; then
        echo "Error: Failed to pull image $image, continuing..."
        failed_count=$((failed_count + 1))
        failed_images="${failed_images} ${image}"
        continue
    fi

    # 提取基础名称（例如 deluan/navidrome:latest -> navidrome:latest）
    base_name=$(echo "$image" | awk -F '/' '{print $NF}')
    # 阿里云用下划线替换斜杠（避免路径冲突）
    name_for_aliyun=$(echo "$base_name" | tr '/' '_')
    targetFullName_aliyun=${TARGET_REGISTRY}/${TARGET_NAMESPACE}/${name_for_aliyun}

    # 打阿里云的 tag
    docker tag "${image}" "${targetFullName_aliyun}"
    # 推送到阿里云
    set +e
    docker push "${targetFullName_aliyun}"
    push_status=$?
    if [ $push_status -ne 0 ]; then
        echo "Error: Failed to push image $targetFullName_aliyun, continuing..."
        failed_count=$((failed_count + 1))
        failed_images="${failed_images} ${image}"
        continue
    fi

    # --- 新增：推送到 Docker Hub ---
    # Docker Hub 目标格式：用户名/仓库名:镜像名（如 maomao1714/mao_hub:deluan_navidrome）
    targetFullName_dockerhub=${DOCKERHUB_USER}/${DOCKERHUB_REPO}:${name_for_aliyun}
    docker tag "${image}" "${targetFullName_dockerhub}"
    docker push "${targetFullName_dockerhub}"
    push_docker_status=$?
    if [ $push_docker_status -ne 0 ]; then
        echo "Warning: Failed to push image $targetFullName_dockerhub to Docker Hub, continuing..."
        # 只警告，不增加失败计数，避免因为 Docker Hub 问题中断整个流程
    fi
    # -----------------------------

done < "$IMAGES_FILE"

if [ $failed_count -gt 0 ]; then
    echo "Error: Failed to sync $failed_count images: $failed_images"
    exit 1
fi
echo "Successfully synced all images."
