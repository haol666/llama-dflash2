
# llama.cpp DFlash2 Docker 镜像

> PR #27342: DFlash2 投机解码（local convolution + candidate selector）  
> 源分支: `z-lab/llama.cpp-fork:dflash2` (commit `5ecbe1ac`)  
> 镜像通过 GitHub Actions 自动构建并发布到 GHCR

## 镜像列表

GitHub Actions 构建完成后，以下镜像可用：

| 镜像 | 标签 | 说明 | 镜像大小 |
|------|------|------|---------|
| `ghcr.io/<owner>/<repo>:cuda` | 多架构 CUDA | 覆盖 70~120 全部主流架构 | ~3.5 GB |
| `ghcr.io/<owner>/<repo>:cuda-75` | Turing 专用 | 2080Ti / T4 / V100 等精简编译 | ~2.5 GB |
| `ghcr.io/<owner>/<repo>:cpu` | 纯 CPU | 无 GPU 依赖，测试用 | ~450 MB |

> 将 `<owner>/<repo>` 替换为你的 GitHub 仓库路径，例如 `ghcr.io/yourname/llama-dflash2:cuda`

## 快速开始

### 1. 拉取镜像

```bash
# GPU 版（多架构）
docker pull ghcr.io/<owner>/<repo>:cuda

# GPU 版（2080Ti 专用，镜像更小）
docker pull ghcr.io/<owner>/<repo>:cuda-75

# CPU 版
docker pull ghcr.io/<owner>/<repo>:cpu
```

### 2. 准备模型

```bash
mkdir -p models && cd models

# 目标模型
wget https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/main/Qwen3.8-27B-UD-Q4_K_XL.gguf

# DFlash2 草稿模型
wget https://huggingface.co/incoai/Qwen3.8-27B-DFlash2-GGUF/resolve/main/Qwen3.8-27B-DFlash2-Q4_K_M.gguf

cd ..
```

### 3. 运行

**Docker Compose（推荐）:**

```bash
cp .env.example .env
# 编辑 .env: IMAGE_OWNER=your-username, 确认模型名

docker compose up -d dflash2-gpu
```

**Docker CLI:**

```bash
docker run -d --gpus all -p 8080:8080 \
  -v $(pwd)/models:/models:ro \
  --shm-size 4g \
  ghcr.io/<owner>/<repo>:cuda \
  -m /models/Qwen3.8-27B-Q4_K_M.gguf \
  -md /models/Qwen3.8-27B-DFlash2-Q4_K_M.gguf \
  --spec-type draft-dflash \
  --spec-draft-n-max 4 \
  -c 32768 -ngl 99 -ngld 99 \
  -fa on -ctk q8_0 -ctv q8_0 \
  --host 0.0.0.0 --port 8080
```

### 4. 测试

```bash
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3.8-27b",
    "messages": [{"role": "user", "content": "你好"}],
    "max_tokens": 100
  }'
```

## GitHub Actions 自动构建

### 工作流程

文件: `.github/workflows/build-dflash2.yml`

```
push 到 main/master ──┐
                      ├──> build-cuda (rapids)  ──> ghcr.io/...:cuda
                      ├──> build-cuda (75)      ──> ghcr.io/...:cuda-75
                      └──> build-cpu            ──> ghcr.io/...:cpu

手动触发 (workflow_dispatch)
  ├── 可选 CUDA_ARCH (75 / 89 / rapids)
  └── 可选是否推送

每周一 UTC 02:00 自动构建（同步上游 dflash2 分支）
```

### 触发构建

1. **自动触发**: push 任何对 `Dockerfile.*` 或 workflow 文件的改动到 `main`/`master`
2. **手动触发**: GitHub 仓库 → Actions → "Build DFlash2 Docker Images" → Run workflow
3. **定时触发**: 每周一自动构建（拉取 z-lab/llama.cpp-fork:dflash2 最新代码）

### 镜像标签策略

```
ghcr.io/<owner>/<repo>:cuda         ← 最新 stable (latest)
ghcr.io/<owner>/<repo>:cuda-20260820  ← 日期快照
ghcr.io/<owner>/<repo>:cuda-5e8f3a2   ← commit SHA
```

## Unraid 部署

### 前提条件

1. 安装 **NVIDIA Driver** 插件 (Community Applications)
2. 安装 **NVIDIA Container Toolkit** 插件
3. Docker vdisk 大小改为 **50GB+** (Settings → Docker)

### 部署步骤

```bash
# 1. 准备目录
mkdir -p /mnt/cache/appdata/llama-dflash2/models
cd /mnt/cache/appdata/llama-dflash2

# 2. 下载 compose 文件和 .env
#    (从你的 GitHub 仓库 raw 链接下载，或通过 SMB 上传)
wget https://raw.githubusercontent.com/<owner>/<repo>/main/docker-compose.yml
wget https://raw.githubusercontent.com/<owner>/<repo>/main/.env.example
cp .env.example .env

# 3. 编辑 .env
nano .env
#    IMAGE_OWNER=your-username
#    TARGET_MODEL=Qwen3.8-27B-Q4_K_M.gguf
#    DRAFT_MODEL=Qwen3.8-27B-DFlash2-Q4_K_M.gguf

# 4. 下载模型到 models/ 目录
cd models
wget <model_url>
cd ..

# 5. 启动
docker compose up -d dflash2-gpu

# 6. 查看日志
docker compose logs -f dflash2-gpu
```

### Unraid WebUI 模板 (可选)

如需在 Unraid WebUI 中管理，在 Add Container 中填入:

| 字段 | 值 |
|------|---|
| Repository | `ghcr.io/<owner>/<repo>:cuda` |
| Extra Parameters | `--gpus all --shm-size=4g` |
| Host Port | `8080` |
| Host Path | `/mnt/cache/appdata/llama-dflash2/models` → `/models` (Read Only) |

### Unraid 注意事项

- **vdisk 大小**: 默认 20GB 不够，改为 50GB+ 或将 docker.img 放到 cache 盘
- **CUDA 架构**: 2080Ti 用 `:cuda-75` 标签，避免拉取多架构大镜像
- **网络**: 国内拉取 ghcr.io 可能耗时，建议提前拉取: `docker pull ghcr.io/...:cuda-75`
- **共享内存**: compose 中已设置 `shm_size: 4g`，CLI 方式需手动加 `--shm-size 4g`

## 三方对比测试

docker-compose.yml 内置 3 个对比服务:

```bash
# 同时启动 DFlash2 / MTP / Baseline
docker compose up -d dflash2-gpu mtp-gpu baseline-gpu

# 分别测试
curl http://localhost:8080/v1/chat/completions  # DFlash2
curl http://localhost:8081/v1/chat/completions  # MTP
curl http://localhost:8082/v1/chat/completions  # Baseline
```

## DFlash2 关键参数

| 参数 | 说明 | 推荐值 |
|------|------|--------|
| `--spec-type draft-dflash` | 启用 DFlash2 | 必填 |
| `--spec-draft-n-max N` | 草稿深度 | **4** (V100), **7** (H100/Blackwell) |
| `-md <model.gguf>` | 草稿模型路径 | 必填 |
| `-ngld 99` | 草稿模型 GPU 层数 | 99 (全部) |
| `-ctk q8_0 -ctv q8_0` | KV cache 量化 | 推荐开启 |

## 已知问题

| 问题 | 绕过方案 |
|------|---------|
| Vision/多模态不可用 (M-RoPE 冲突) | 不使用图片输入；等 z-lab#1 修复合入 |
| Windows MSVC 编译失败 | 使用 Docker(Linux) 构建，已绕过 |
| 多并发退化 (Intel B70) | 限制 `-np 1` 单并发使用 |
| 编译时 OOM | 修改 Dockerfile 中 `-j$(nproc)` 为 `-j4` |

## 文件结构

```
llama-dflash2/
├── .github/workflows/
│   └── build-dflash2.yml    # GitHub Actions CI/CD
├── .env.example             # 环境变量模板
├── Dockerfile.cuda          # CUDA GPU 构建
├── Dockerfile.cpu           # CPU-only 构建
├── docker-compose.yml       # 编排文件 (GPU+CPU+对比)
├── build.sh                 # 本地构建/运行脚本
└── README.md                # 本文档
```
