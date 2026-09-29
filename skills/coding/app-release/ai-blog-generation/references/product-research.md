# 产品实物调研与视觉特征提取

> 本文件配套 `skills/coding/app-release/ai-blog-generation/SKILL.md`（步骤 ③）。产品实物调研与视觉特征提取——外部官网/搜索引擎访问（合法）。

## 执行条件

**仅当博客主题涉及具体产品或品牌时执行此步骤。** 如主题为抽象概念、通用知识、纯教程，则跳过此步。

## A3a. 定位产品官网

从 Issue 需求中提取产品/品牌名称（如「华为问界M9」「iPhone 16」「理想L9」），通过搜索引擎定位其**中国大陆官方网站**：

```bash
# 示例：搜索品牌官网
curl -sL "https://www.baidu.com/s?wd=<产品名>+官方网站" \
  -H "User-Agent: Mozilla/5.0" | python3 -c "
import sys, re
html = sys.stdin.read()
# 提取搜索结果中的 URL
urls = re.findall(r'https?://[^\s\"<>]+', html)
# 过滤并输出最可能的官网
for u in urls:
    if any(dom in u for dom in ['huawei', 'apple', 'xiaomi', 'oppo', 'vivo',
           'honor', 'lenovo', 'dji', 'ideal', 'xpeng', 'nio', 'byd', 'mitsubishi',
           'toyota', 'honda', 'audi', 'bmw', 'mercedes', 'ford']):
        print(u)
        break
"
```

如果自动化提取失败，允许手动打开浏览器访问：

```python
# 使用 browser_navigate + browser_console 访问官网取图
browser_navigate(f"https://www.{product_brand}.com/{product_model}")
# 提取产品图片 URL
browser_console(expression="[...document.querySelectorAll('img[src*=\"product\"]')].map(i=>i.src)")
```

## A3b. 提取视觉特征

收集到真实产品图片后，从以下维度分析视觉特征并记录到临时文件供后续使用：

```python
# 保存到 /tmp/blog-gen-{pid}/product_visual_info.json
visual_info = {
    "brand": "华为",
    "product": "问界M9",
    "colors": ["星河蓝", "陶瓷白", "深空灰"],          # 官网提供的车身颜色
    "design": {
        "front": "封闭式前脸+贯穿式日行灯+HUAWEI标识",
        "side": "流线型车身+隐藏式门把手+双色轮毂",
        "rear": "贯穿式尾灯+AITO标识"
    },
    "interior": "三屏中控+平底方向盘+Nappa真皮座椅",
    "logo": "AITO logo 在车头/方向盘/轮毂",
    "scene": "城市道路/高速/充电站/家庭出行",
    "reference_urls": ["https://aito.auto/m9/gallery"]  # 图片来源
}
```

## A3c. 将视觉特征注入生成提示词

在后续图片生成和视频生成中，**必须**将 `visual_info` 中的实际产品特征嵌入到 prompt 中，确保生成结果与实物一致：

```
# 图片生成 prompt 中加入品牌/颜色/设计细节
prompt = f"""
{theme_prompt}。画面中的车辆必须是{visual_info['brand']}{visual_info['product']}，
采用{visual_info['colors'][0]}车身配色，{visual_info['design']['front']}的经典前脸设计，
{visual_info['design']['side']}侧面轮廓，{visual_info['logo']}品牌标识清晰可见。
风格：写实产品渲染，高质感光影，8K细节。
"""
```

**严禁**仅凭模型预训练记忆生成产品外观——实际产品的颜色、logo位置、前脸格栅造型、轮毂样式等细节必须来自官网提取的真实信息。

## A3d. 提取真实产品 Logo 并保存

下载一张官网的正面/前侧方产品图，用 Pillow 裁剪出 logo 区域并保存为透明 PNG。**后续所有图片生成后，必须将真实 logo 叠加到图上**，因为 AI 文生图模型无法准确还原品牌 logo。

```python
from PIL import Image
import os, json

# 读取已保存的 visual_info
with open(f"/tmp/blog-gen-{os.getpid()}/product_visual_info.json") as f:
    vi = json.load(f)

# 从 reference_urls 中选一个正面清晰的产品图下载
import urllib.request
real_img_url = vi.get("reference_urls", [])[0]  # 第一张官方图
urllib.request.urlretrieve(real_img_url, f"/tmp/blog-gen-{os.getpid()}/real_product.jpg")

# 打开并裁剪 logo 区域（位置需要根据图片类型估计）
# 全尺寸SUV前脸：logo 约在宽度 40-58%、高度 20-38% 区域
img = Image.open(f"/tmp/blog-gen-{os.getpid()}/real_product.jpg")
w, h = img.size
logo_box = (int(w*0.42), int(h*0.22), int(w*0.58), int(h*0.38))
logo = img.crop(logo_box)

# 缩放至合适大小并去底（白色背景→透明）
logo_small = logo.resize((80, 80), Image.LANCZOS)
logo_rgba = logo_small.convert("RGBA")
pixels = logo_rgba.load()
for y in range(logo_rgba.height):
    for x in range(logo_rgba.width):
        r, g, b, a = logo_rgba.getpixel((x, y))
        if r > 220 and g > 220 and b > 220:
            logo_rgba.putpixel((x, y), (r, g, b, 0))

logo_rgba.save(f"/tmp/blog-gen-{os.getpid()}/logo_overlay.png")
print(f"Logo extracted: {logo_rgba.size} with transparency")

# 记录不同图型的 logo 叠加位置
logo_positions = {
    "cover":       (int(w*0.47), int(h*0.28)),  # 封面/前脸车标
    "theme_1":     (int(w*0.47), int(h*0.28)),  # 前脸主题
    "theme_2":     (int(w*0.30), int(h*0.50)),  # 内饰/方向盘
    "theme_3":     (int(w*0.47), int(h*0.30)),  # 座舱主题
    "theme_4":     (int(w*0.47), int(h*0.28)),  # 驾驶场景
    "theme_5":     (int(w*0.48), int(h*0.55)),  # 尾部场景
}
with open(f"/tmp/blog-gen-{os.getpid()}/logo_positions.json", "w") as f:
    json.dump(logo_positions, f)
```

> ⚠️ **字体版权警告**：从官网图片裁剪的 logo 仅供 AI 增强配图使用，不得作为独立素材分发或商用。
