#!/bin/bash
set -euo pipefail

# ============================================
# 用法: ./sync.sh <images_file> <docker_registry> <docker_namespace>
# 功能：拉取 images.txt 中的最新镜像，直接推送到阿里云和 Docker Hub（覆盖旧版本）
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

if [ ! -f "$IMAGES_FILE" ]; then
    echo "错误：文件 $IMAGES_FILE 不存在"
    exit 1
fi

total_images=0
failed_count=0
failed_images=""

while IFS= read -r image; do
    # 跳过空行和以 # 开头的注释行
    [[ -z "$image" || "$image" =~ ^# ]] && continue

    total_images=$((total_images + 1))
    echo "=========================================="
    echo ">>> 处理镜像 (${total_images}): $image"

    # ---------- 1. 拉取源镜像（最新版本）----------
    echo ">>> 拉取镜像 (平台: linux/arm64)..."
    if ! docker pull --platform linux/arm64 "$image"; then
        echo "❌ 错误：拉取镜像失败，跳过。"
        failed_count=$((failed_count + 1))
        failed_images="${failed_images} ${image}"
        continue
    fi

    # ---------- 2. 推送到阿里云 ----------
    base_name=$(echo "$image" | awk -F '/' '{print $NF}')
    name_for_aliyun=$(echo "$base_name" | tr '/' '_')
    target_aliyun="${TARGET_REGISTRY}/${TARGET_NAMESPACE}/${name_for_aliyun}"

    echo ">>> 推送至阿里云: $target_aliyun"
    docker tag "$image" "$target_aliyun"
    if docker push "$target_aliyun"; then
        echo "✅ 阿里云推送成功"
    else
        echo "❌ 阿里云推送失败"
        failed_count=$((failed_count + 1))
        failed_images="${failed_images} ${image}"
        # 即使阿里云失败，继续尝试推送 Docker Hub
    fi

    # ---------- 3. 推送到 Docker Hub ----------
    dockerhub_tag=$(echo "$image" | sed 's/[\/:]\+/_/g' | tr '[:upper:]' '[:lower:]')
    target_dockerhub="${DOCKERHUB_USER}/${DOCKERHUB_REPO}:${dockerhub_tag}"

    echo ">>> 推送至 Docker Hub: $target_dockerhub"
    docker tag "$image" "$target_dockerhub"
    if docker push "$target_dockerhub"; then
        echo "✅ Docker Hub 推送成功"
    else
        echo "❌ Docker Hub 推送失败"
        failed_count=$((failed_count + 1))
        failed_images="${failed_images} ${image}"
    fi

    # ---------- 4. 清理本地镜像以节省空间 ----------
    docker rmi "$image" "$target_aliyun" "$target_dockerhub" > /dev/null 2>&1 || true

done < "$IMAGES_FILE"

# ---------- 最终报告 ----------
echo "=========================================="
echo "📊 同步任务完成。"
echo "处理镜像总数: $total_images"
echo "失败镜像数: $failed_count"
if [ $failed_count -gt 0 ]; then
    echo "❌ 失败镜像列表: $failed_images"
    exit 1
fi
echo "✅ 所有镜像处理成功。"            echo "✅ Docker Hub 镜像已存在且 digest 相同，跳过推送: $target_dockerhub"
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
