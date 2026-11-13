# ctx 扩容实测矩阵（RTX 4090 24GB · Q4_K_M + mtp draft · mmproj CPU 驻留）

- 日期：2026-11-13 · 方法：临时实例 :8010 逐档起停，`nvidia-smi` compute 侧显存 + 200 token 生成计时
- 前提：权重 ~18.6GB · 桌面 GUI ~0.4GB 不计入 compute 侧

## 矩阵结果

| ctx | KV native | KV q8_0 |
|-----|-----------|---------|
| 32K | ✅ 21710MiB · 1.2s/200tok | ✅ 20750MiB · 1.0s/200tok |
| 64K | ❌ 段错误（显存不足） | ✅ **22000MiB · 1.6s/200tok** |
| 128K | ❌ | ❌ |

## 结论（选定默认档）

- **默认 64K + KV q8_0**（用户 2026-11-13 确认）：上下文翻倍（vs 32K），显存 22000MiB 含桌面后余 ~2.1GB，速度基本无损
- q8_0 量化 KV 显存减半、实测速度不降反略升 → 零成本门票
- 128K+ 双路 OOM（llama.cpp b9378 表现为段错误 — onekey「进程退出」兜底可捕获）
- 模型原生上限 256K（`n_ctx_train=262144`）— 24GB 单卡到此为止；更大 ctx 需多卡或 KV CPU offload（未来候选）

## 复跑

```bash
# 临时实例示例（单档）
llama-server -m <model> --model-draft <draft> --spec-type draft-mtp \
  --port 8010 --ctx-size 65536 --cache-type-k q8_0 --cache-type-v q8_0 \
  --n-gpu-layers 999 --flash-attn on --jinja
```
