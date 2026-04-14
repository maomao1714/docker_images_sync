#!/bin/bash
set -euo pipefail

# ============================================
# 用法: ./sync.sh <images_file> <docker_registry> <docker_namespace>
# ============================================

if [ "$#" -ne 3 ]; then
    echo "错误：脚本需要3个参数 images_file、docker_registry 和 docker_namespace"
    echo "用法: $0 <images_file> <docker_registry> <docker_namespace>"
    exit 1
fi

IMAGES_FILE="$1"
TARGET_REGISTRY="$2"
TARGET_NAMESPACE="$3"

# Docker Hub 目标仓库配置（请根据实际情况修改）
DOCKERHUB_USER="maomao1714"
DOCKERHUB_REPO="mao_hub"

# 检查文件是否存在
if [ ! -f "$IMAGES_FILE" ]; then
    echo "错误：文件 $IMAGES_FILE 不存在"
    exit 1
fi

# 计数器
total_images=0
skipped_count=0
failed_count=0
failed_images=""

# 逐行读取镜像列表
while IFS= read -r image; do
    # 跳过空行和以 # 开头的注释行
    [[ -z "$image" || "$image" =~ ^# ]] && continue

    total_images=$((total_images + 1))
    echo "=========================================="
    echo ">>> 处理镜像 (${total_images}): $image"

    # ---------- 1. 拉取镜像 ----------
    echo ">>> 拉取镜像 (平台: linux/arm64)..."
    if ! docker pull --platform linux/arm64 "$image"; then
        echo "❌ 错误：拉取镜像失败，跳过。"
        failed_count=$((failed_count + 1))
        failed_images="${failed_images} ${image}"
        continue
    fi

    # ---------- 2. 获取本地镜像 digest ----------
    local_digest=$(docker inspect --format='{{index .RepoDigests 0}}' "$image" 2>/dev/null | cut -d '@' -f2)
    if [ -z "$local_digest" ]; then
        echo "❌ 错误：无法获取镜像 digest，跳过。"
        failed_count=$((failed_count + 1))
        failed_images="${failed_images} ${image}"
        continue
    fi
    echo "本地 digest: $local_digest"

    # ---------- 3. 准备阿里云目标名称 ----------
    base_name=$(echo "$image" | awk -F '/' '{print $NF}')
    name_for_aliyun=$(echo "$base_name" | tr '/' '_')
    target_aliyun="${TARGET_REGISTRY}/${TARGET_NAMESPACE}/${name_for_aliyun}"

    # ---------- 4. 检查阿里云仓库是否需要推送 ----------
    push_aliyun=false
    if docker manifest inspect "$target_aliyun" > /dev/null 2>&1; then
        remote_digest=$(docker manifest inspect "$target_aliyun" 2>/dev/null | grep -o '"digest":"[^"]*"' | head -1 | cut -d '"' -f4)
        if [ "$remote_digest" = "$local_digest" ]; then
            echo "✅ 阿里云镜像已存在且 digest 相同，跳过推送: $target_aliyun"
        else
            echo "🔄 阿里云镜像存在但 digest 不同，将更新推送: $target_aliyun"
            push_aliyun=true
        fi
    else
        echo "➕ 阿里云镜像不存在，将首次推送: $target_aliyun"
        push_aliyun=true
    fi

    # 执行阿里云推送
    if [ "$push_aliyun" = true ]; then
        docker tag "$image" "$target_aliyun"
        if docker push "$target_aliyun"; then
            echo "✅ 阿里云推送成功"
        else
            echo "❌ 错误：阿里云推送失败"
            failed_count=$((failed_count + 1))
            failed_images="${failed_images} ${image}"
            # 继续尝试 Docker Hub，不跳过后续步骤
        fi
    fi

    # ---------- 5. 准备 Docker Hub 目标名称 ----------
    dockerhub_tag=$(echo "$image" | sed 's/[\/:]\+/_/g' | tr '[:upper:]' '[:lower:]')
    target_dockerhub="${DOCKERHUB_USER}/${DOCKERHUB_REPO}:${dockerhub_tag}"

    # ---------- 6. 检查 Docker Hub 是否需要推送 ----------
    push_dockerhub=false
    if docker manifest inspect "$target_dockerhub" > /dev/null 2>&1; then
        remote_digest=$(docker manifest inspect "$target_dockerhub" 2>/dev/null | grep -o '"digest":"[^"]*"' | head -1 | cut -d '"' -f4)
        if [ "$remote_digest" = "$local_digest" ]; then
            echo "✅ Docker Hub 镜像已存在且 digest 相同，跳过推送: $target_dockerhub"
        else
            echo "🔄 Docker Hub 镜像存在但 digest 不同，将更新推送: $target_dockerhub"
            push_dockerhub=true
        fi
    else
        echo "➕ Docker Hub 镜像不存在，将首次推送: $target_dockerhub"
        push_dockerhub=true
    fi

    # 执行 Docker Hub 推送
    if [ "$push_dockerhub" = true ]; then
        docker tag "$image" "$target_dockerhub"
        if docker push "$target_dockerhub"; then
            echo "✅ Docker Hub 推送成功"
        else
            echo "❌ 错误：Docker Hub 推送失败"
            failed_count=$((failed_count + 1))
            failed_images="${failed_images} ${image}"
        fi
    fi

    # ---------- 7. 清理本地镜像以节省空间 ----------
    docker rmi "$image" "$target_aliyun" "$target_dockerhub" > /dev/null 2>&1 || true

    if [ "$push_aliyun" = false ] && [ "$push_dockerhub" = false ]; then
        skipped_count=$((skipped_count + 1))
    fi

done < "$IMAGES_FILE"

# ---------- 最终报告 ----------
echo "=========================================="
echo "同步任务完成。"
echo "处理镜像总数: $total_images"
echo "完全跳过（两边均已存在）: $skipped_count"
echo "失败镜像数: $failed_count"
if [ $failed_count -gt 0 ]; then
    echo "失败镜像列表: $failed_images"
    exit 1
fi
echo "所有镜像处理成功。"
