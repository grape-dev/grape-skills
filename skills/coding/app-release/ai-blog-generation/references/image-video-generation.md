# 图片与视频生成

> 本文件从 SKILL.md 步骤 4、5 拆分。包含配图生成、视频生成和音视频合成。

## 4. 生成配图

从项目知识中获取 qwen-image 的 API Key 和 URL，调用 ModelArts 图片生成 API：

```python
import requests, json, base64, os, time

# API 信息从项目知识读取（ai_models.image.url / .key / .model）
API_IMAGE = image_url
KEY_IMAGE = image_key
MODEL_IMAGE = image_model
headers = {"Authorization": f"Bearer {KEY_IMAGE}", "Content-Type": "application/json"}

# 先以本地临时目录生成，后续步骤统一迁入 blog/
IMG_DIR = f"/tmp/blog-gen-{os.getpid()}/images"
os.makedirs(IMG_DIR, exist_ok=True)

# 各配图 prompt 构造，优先使用步骤 3 提取的 visual_info
themes = [
    # 如果 product_visual_info.json 存在，每个 prompt 自动嵌入实际产品特征
    {"prompt": "主题1的详细画面描述，须包含product品牌+型号+颜色等真实视觉特征", "file": "theme_1"},
]

for i, t in enumerate(themes):
    resp = requests.post(API_IMAGE, headers=headers, json={"model": MODEL_IMAGE, "prompt": t["prompt"], "n": 1, "size": "1024x1024"}, timeout=60)
    b64 = resp.json()["data"][0]["b64_json"]
    if "," in b64: b64 = b64.split(",")[1]
    with open(f"{IMG_DIR}/{t['file']}.png", "wb") as f: f.write(base64.b64decode(b64))

    # 图片生成后立即叠加真实 logo（如存在）
    logo_overlay = f"/tmp/blog-gen-{os.getpid()}/logo_overlay.png"
    logo_pos = f"/tmp/blog-gen-{os.getpid()}/logo_positions.json"
    if os.path.exists(logo_overlay) and os.path.exists(logo_pos):
        try:
            from PIL import Image
            with open(logo_pos) as f:
                positions = json.load(f)
            pos = positions.get(t['file'], positions.get("cover", (480, 280)))
            ai_img = Image.open(f"{IMG_DIR}/{t['file']}.png").convert("RGBA")
            logo = Image.open(logo_overlay).convert("RGBA")
            ai_img.paste(logo, pos, logo)
            ai_img.convert("RGB").save(f"{IMG_DIR}/{t['file']}.png")
            size_kb = os.path.getsize(f"{IMG_DIR}/{t['file']}.png") / 1024
            print(f"  [logo] 叠加到 {t['file']}.png ({size_kb:.0f}KB)")
        except Exception as e:
            print(f"  [logo] 叠加失败: {e}")
    # 限流间隔
    if i < len(themes) - 1: time.sleep(1)
```

## 5. 生成视频

从项目知识中获取视频生成模型的 API Key、URL 和 Model（`ai_models.video`）。
⚠️ **禁止使用 I2V（图生视频）模型**——只能使用 T2V（文生视频）模型。模型名中含 `I2V`（如 `Wan2.2-I2V-A14B`）的一律不得调用，需在项目知识中配置 T2V 模型（如 `Wan2.2-T2V-A14B`）。

视频 prompt 必须基于步骤 3 提取的 `visual_info` 来构造准确的产品外观描述：

```python
import requests, json, time
import os

# 模型校验：禁止 I2V 模型
MODEL_VIDEO = video_model
assert "I2V" not in MODEL_VIDEO.upper(), f"禁止使用 I2V 模型({MODEL_VIDEO})，请配置 T2V 模型"

# 尝试加载产品视觉特征（如存在）
VIDEO_PROMPT = "英文画面描述"  # 默认fallback
product_info_path = f"/tmp/blog-gen-{os.getpid()}/product_visual_info.json"
if os.path.exists(product_info_path):
    with open(product_info_path) as f:
        vi = json.load(f)
    VIDEO_PROMPT = (
        f"Realistic 5-second cinematic shot of a {vi['brand']} {vi['product']} "
        f"in {vi['colors'][0]} color, driving on a modern city road at sunset. "
        f"The vehicle features {vi['design']['front']}, {vi['design']['side']}. "
        f"Camera slowly pans from front 3/4 view to side profile. "
        f"Clean background, professional automotive cinematography, 4K, photorealistic."
    )

API_VIDEO = video_url
KEY_VIDEO = video_key
H = {"Authorization": f"Bearer {KEY_VIDEO}", "Content-Type": "application/json"}

resp = requests.post(API_VIDEO, headers=H, json={
    "model": MODEL_VIDEO,       # 必须是 T2V 模型（如 Wan2.2-T2V-A14B）
    "input": {"prompt": VIDEO_PROMPT}
}, timeout=30)
task_id = resp.json()["task_id"]
time.sleep(30)
result = requests.get(f"{API_VIDEO}/{task_id}", headers=H).json()
if result['status'] == 'succeeded':
    video_url = result['content']['result_url']
```

下载并合成音视频：

```bash
TMP_DIR="/tmp/blog-gen-$$"
mkdir -p "$TMP_DIR"
curl -sLo "$TMP_DIR/generated.mp4" "$video_url"
edge-tts --voice zh-CN-XiaoxiaoNeural --text "旁白文案，18-22字" --write-media "$TMP_DIR/narration.mp3"
ffmpeg -y -i "$TMP_DIR/narration.mp3" -t 5 -af "afade=t=out:st=4.5:d=0.5" "$TMP_DIR/audio_trim.mp3"
ffmpeg -y -i "$TMP_DIR/generated.mp4" -i "$TMP_DIR/audio_trim.mp3" \
  -c:v libx264 -crf 23 -preset fast -c:a aac -b:a 128k \
  -map 0:v:0 -map 1:a:0 -shortest "$TMP_DIR/intro.mp4"
```
