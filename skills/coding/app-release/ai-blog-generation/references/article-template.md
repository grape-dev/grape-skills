# HTML 文章模板与样式

> 本文件配套 `skills/coding/app-release/ai-blog-generation/SKILL.md`（步骤 ②）。提供博客文章的 HTML 模板和内联样式。

## 推荐内联样式结构

```html
<!DOCTYPE html>
<html>
<head>
<style>
body { font-family: -apple-system, 'PingFang SC', sans-serif; background: #f5f7fa; }
.article { max-width: 860px; margin: 0 auto; background: #fff; padding: 40px 50px; }
h1 { font-size: 28px; font-weight: 700; color: #1a1a2e; }
h2 { font-size: 22px; border-left: 4px solid #0d6efd; padding-left: 12px; }
.figure img { max-width: 100%; border-radius: 8px; box-shadow: 0 2px 12px rgba(0,0,0,0.1); }
blockquote { background: #f0f4ff; border-left: 4px solid #0d6efd; padding: 16px 20px; border-radius: 0 8px 8px 0; }
.highlight { background: linear-gradient(135deg, #0d6efd, #6610f2); color: #fff; padding: 24px; border-radius: 12px; }
.tag { display: inline-block; padding: 3px 12px; background: #e8f0fe; color: #0d6efd; border-radius: 12px; font-size: 12px; }
table { width: 100%; border-collapse: collapse; }
th { background: #f0f4ff; padding: 12px 16px; border: 1px solid #e0e6ed; }
td { padding: 12px 16px; border: 1px solid #e0e6ed; }
</style>
</head>
<body>
<div class="article">
  <!-- 文章内容 -->
</div>
</body>
</html>
```

## 文章内容要求

- 标题 + 元数据（时间、标签、阅读量）
- 顶部嵌入视频（5s 介绍视频）
- 配图间隔分布（每 1-2 段插一张）
- 至少一个特殊元素（表格 / 引用块 / 高亮块）
- 结尾署名
