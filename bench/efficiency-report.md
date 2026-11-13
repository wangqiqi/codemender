# 推理效率优化实测（RTX 4090 · Q4_K_M + mtp · 64K ctx · KV q8_0 · mmproj CPU 驻留）

- 日期：2026-11-13 · 方法：临时实例 :8010 AB 实测（python 毫秒计时）· SPRINT-09

## 结果与决策

| 项 | 实测 | 决策 |
|----|------|------|
| **ubatch 512→2048** | 生成 200tok：1.8s→**1.3s**（**-28%**）· 显存 +888MiB（22888MiB） | ✅ **启用为默认**（`TESS_UBATCH=2048`） |
| KV q8_0→q5_1 | 生成 200tok：1.5s→**5.0s**（**慢 3.3×**）· 显存仅省 754MiB | ❌ **不启用**（速度/显存双输；质量未验已无意义） |
| `--cache-reuse 512` | 同前缀 prefill：无该开关时**默认已 74ms**（vs 首跑 6535ms = **89×**）· 开关无额外收益 | ❌ 不配置（默认机制已覆盖 batch_review 场景） |
| 128K ctx | q8_0 OOM；q5_1 能起（23418MiB）但生成 4.0s 慢 | ❌ 维持 64K（q5_1 的 128K 不可接受） |
| draft KV 量化 | 未测（预估省几百 MiB 边际收益） | backlog |

## 已在用（历史已落地）

flash-attn ✓ · draft-mtp 投机（接受率 49.7/76.6%）✓ · KV q8_0 ✓ · mmproj CPU 驻留（省 1.2GB）✓ · 重复前缀 prompt cache（默认自带 89×）✓

## 结论

24GB 单卡 + 27B 的合理终点：**64K ctx + KV q8_0 + ubatch 2048 + mmproj CPU 驻留** — 生成效率较本轮起点提升 ~28%，上下文较最初 32K 翻倍。更大 ctx 需多卡/KV CPU offload。

## 复跑要点

prefill/生成计时须用 python 毫秒级（bash `%s.%N` 在 <100ms 时失真）；临时实例实验前**必须先 stop 正式服**（权重 buffer 15.8GB 需整块显存）。
